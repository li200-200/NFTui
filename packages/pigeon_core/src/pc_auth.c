/* ---------------------------------------------------------------------------
 * 认证模块实现。
 *
 * 校验规则集中在本文件的 pc_form_* 三个函数里，validate_ 与业务接口共用 ——
 * 这是刻意的：校验规则与「要不要发请求」是两件事，但「同一份规则」只有一处，
 * 否则页面上先过后不过、或者先不过后过，都会变成很难复现的偶发问题。
 *
 * 业务接口的流程：
 *   1. 表单校验（纯本地）—— 没过就直接返回，不产生任何网络流量；
 *   2. 组参数、发请求；
 *   3. 把服务端的结论原样搬进 pc_auth_result。
 *
 * 账号能否通过完全由服务端裁决。这里没有任何「本地也能判定账号」的分支。
 * ------------------------------------------------------------------------- */

#include "pc_auth.h"

#include <stdio.h>
#include <string.h>
#include <time.h>

#ifdef _WIN32
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0600 /* SRWLOCK 需要 Vista+ */
#endif
#include <windows.h>
#endif

#include "pc_authnet.h"
#include "pc_bsphp.h"
#include "pc_common.h"
#include "pc_log.h"

/* 用户名/卡密复制到请求参数时用的缓冲。真实账号 16 位、卡密 16 位，
   128 足够；超长的输入会在下面被截断到缓冲长度，而它本来也过不了校验。 */
#define PC_ARG_BUF 128

/* ===========================================================================
 * 结果初始化
 * ========================================================================= */

static void pc_result_reset(pc_auth_result* out) {
  out->status = PC_OK;
  out->form.user = PC_FIELD_OK;
  out->form.pwd = PC_FIELD_OK;
  out->form.pwd2 = PC_FIELD_OK;
  out->form.card = PC_FIELD_OK;
  out->form.pwd_acc = PC_FIELD_OK;
  out->form.form_ok = 0;
  out->message[0] = '\0';
  out->data[0] = '\0';
}

static int pc_slots_ok(const pc_form_result* form) {
  return (form->user == PC_FIELD_OK) && (form->pwd == PC_FIELD_OK) &&
         (form->pwd2 == PC_FIELD_OK) && (form->card == PC_FIELD_OK) &&
         (form->pwd_acc == PC_FIELD_OK);
}

/* 把裁剪后的视图复制成 NUL 结尾的独立字符串。
 *
 * pc_trim 返回的是原串上的视图，尾部可能还挂着空格、也不是独立字符串。
 * 提交给接口的参数值必须是干净字符串，所以每次都要复制一份。 */
static void pc_slice_to_buf(const pc_slice* s, char* buf, size_t cap) {
  size_t n;
  /* cap == 0 时 cap - 1 会下溢成 SIZE_MAX，n 直接取 s->len —— 越界写调用方缓冲。
   * 这个助手是 static、调用点目前都传常量容量，但「当前没被误用」不等于安全：
   * 加一行判空，把这个前置条件从注释里的约定变成代码里的保证。 */
  if (buf == NULL || cap == 0) return;
  if (s == NULL) { buf[0] = '\0'; return; }
  n = s->len < cap - 1 ? s->len : cap - 1;

  /* 截断落在 UTF-8 字符边界上，避免下游严格解码抛异常。 */
  if (s->ptr != NULL) {
    n = pc_utf8_fit(s->ptr, n);
    if (n > 0) {
      memcpy(buf, s->ptr, n);
    }
  }
  buf[n] = '\0';
}

/* ===========================================================================
 * 逐字段校验（规则只有这一份）
 * ========================================================================= */

/* 「没填 / 太短 / 太长 / 通过」。空与太短互斥：trim 后为空就是没填，
   不该再报长度不够 —— 用户看到的红框数量要能对上他心里的「哪几栏是空的」。
   short_code 由调用方给：密码用 TOO_SHORT，卡密用 BAD_CARD。
   超过 max_len 一律 TOO_LONG（超长输入会被传输层截断，必须本地先挡住）。 */
static int32_t pc_field_length(const pc_slice* s, size_t min_len,
                               size_t max_len, int32_t short_code) {
  size_t n;

  if (s->len == 0) {
    return PC_FIELD_EMPTY;
  }
  n = pc_utf8_count(s);
  if (n < min_len) {
    return short_code;
  }
  /* 上限只防「传输层静默截断」，不是服务端规则（见 pc_auth.h）。 */
  if (n > max_len) {
    return PC_FIELD_TOO_LONG;
  }
  return PC_FIELD_OK;
}

/* 用户名：先看长度区间的两个端点，再看字符集。先长度后字符集，
   用户一次只会看到一类问题。 */
static int32_t pc_field_username(const pc_slice* s) {
  size_t n;
  size_t i;

  if (s->len == 0) {
    return PC_FIELD_EMPTY;
  }
  n = pc_utf8_count(s);
  if (n < PC_USER_MIN_LEN || n > PC_USER_MAX_LEN) {
    return PC_FIELD_BAD_LENGTH;
  }
  for (i = 0; i < s->len; i++) {
    unsigned char c = (unsigned char)s->ptr[i];
    int alnum = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') ||
                (c >= 'A' && c <= 'Z');
    if (!alnum) {
      /* 非 ASCII（比如汉字）也走这里：UTF-8 的续字节 >= 0x80，天然不合法。 */
      return PC_FIELD_BAD_CHARS;
    }
  }
  return PC_FIELD_OK;
}

/* 登录：用户名 + 密码。返回 1 = 全部通过。
   所有字段都会写一遍，调用方不需要预清零。 */
static int pc_form_login(const pc_slice* u, const pc_slice* p,
                         pc_form_result* form) {
  form->user = pc_field_username(u);
  form->pwd = pc_field_length(p, PC_PWD_MIN_LEN, PC_PWD_MAX_LEN,
                             PC_FIELD_TOO_SHORT);
  form->pwd2 = PC_FIELD_OK;
  form->card = PC_FIELD_OK;
  form->pwd_acc = PC_FIELD_OK;
  form->form_ok = pc_slots_ok(form) ? 1 : 0;
  return form->form_ok;
}

/* 注册：四个字段。pwd2 是「确认密码」，只在本地比对 —— 服务端接口没有这个参数。 */
static int pc_form_register(const pc_slice* u, const pc_slice* p,
                            const pc_slice* p2, const pc_slice* c,
                            pc_form_result* form) {
  form->user = pc_field_username(u);
  form->pwd = pc_field_length(p, PC_PWD_MIN_LEN, PC_PWD_MAX_LEN,
                             PC_FIELD_TOO_SHORT);

  /* 确认密码：空 → EMPTY；非空但与密码不同 → MISMATCH。
     刻意不判断「密码是否为空」—— p2 有值而 p 为空时落到「不一致」，
     这是页面上更自然的解读（用户确实两次输入不一样）。 */
  if (p2->len == 0) {
    form->pwd2 = PC_FIELD_EMPTY;
  } else if (!pc_slice_equal(p2, p)) {
    form->pwd2 = PC_FIELD_MISMATCH;
  } else {
    form->pwd2 = PC_FIELD_OK;
  }

  form->card = pc_field_length(c, PC_CARD_MIN_LEN, PC_CARD_MAX_LEN,
                               PC_FIELD_BAD_CARD);
  form->pwd_acc = PC_FIELD_OK;
  form->form_ok = pc_slots_ok(form) ? 1 : 0;
  return form->form_ok;
}

/* 充值：用户名 / 账号密码 / 卡密。 */
static int pc_form_recharge(const pc_slice* u, const pc_slice* cf,
                            const pc_slice* k, pc_form_result* form) {
  /* 用户名在这一页只判空：官方充值接口的 UserName 只是「给谁充」，
     没有长度与字符集的约束（那些约束在注册时就已经定死了）。 */
  form->user = (u->len == 0) ? PC_FIELD_EMPTY : PC_FIELD_OK;
  form->pwd = PC_FIELD_OK;
  /* pwd2 只留给「确认密码」（注册页），充值页不占用它。 */
  form->pwd2 = PC_FIELD_OK;

  /* 充值页的「账号密码」独占 pwd_acc 槽位 —— chong.lg 的 userpwd，服务端要用
     它校验给谁充值，传空会被判「密码错误」（实测 code=1009）。
     规则与登录 / 注册的密码一致：空 → EMPTY，不足 6 位 → TOO_SHORT。 */
  form->pwd_acc = pc_field_length(cf, PC_PWD_MIN_LEN, PC_PWD_MAX_LEN,
                                  PC_FIELD_TOO_SHORT);

  form->card = pc_field_length(k, PC_CARD_MIN_LEN, PC_CARD_MAX_LEN,
                               PC_FIELD_BAD_CARD);
  form->form_ok = pc_slots_ok(form) ? 1 : 0;
  return form->form_ok;
}

/* ===========================================================================
 * 第一段：只校验，不发请求
 * ========================================================================= */

int32_t pc_auth_validate_login_impl(const char* user, const char* pwd,
                                    pc_form_result* out) {
  /* 用户名 trim，密码不 trim：密码里的首尾空格是内容的一部分。 */
  pc_slice u = pc_trim(user);
  pc_slice p = pc_slice_of(pwd);

  return pc_form_login(&u, &p, out) ? PC_OK : PC_ERR_FORM;
}

int32_t pc_auth_validate_register_impl(const char* user, const char* pwd,
                                       const char* pwd2, const char* card,
                                       pc_form_result* out) {
  pc_slice u = pc_trim(user);
  pc_slice p = pc_slice_of(pwd);
  pc_slice p2 = pc_slice_of(pwd2);
  pc_slice c = pc_trim(card);

  return pc_form_register(&u, &p, &p2, &c, out) ? PC_OK : PC_ERR_FORM;
}

int32_t pc_auth_validate_recharge_impl(const char* user, const char* confirm,
                                       const char* card, pc_form_result* out) {
  pc_slice u = pc_trim(user);
  /* 第二栏现在是密码：不 trim —— 密码里的首尾空格是内容的一部分。 */
  pc_slice cf = pc_slice_of(confirm);
  pc_slice k = pc_trim(card);

  return pc_form_recharge(&u, &cf, &k, out) ? PC_OK : PC_ERR_FORM;
}

/* ===========================================================================
 * 第二段：校验通过后发真实请求
 *
 * 后台是 BSPHP（协议实现见 pc_bsphp.c，流程对齐
 * BSPHP-C-DEMO-LOGIN\main.c）：本地表单校验（pc_form_*）完全不动，只把
 * 「发请求 + 解析响应」换成 BSPHP 的
 *   login.lg（登录）/ registrationaska.lg（卡注册）/ chong.lg（充值）/ gg.in（公告）
 * ========================================================================= */

/* 有界字符串拷贝（pc_authnet.c 里的 pc_copy_str 是它自己的 static，不能复用）。 */
static void pc_auth_copy(char* dst, size_t cap, const char* src) {
  size_t n;
  if (dst == NULL || cap == 0) return;
  if (src == NULL) src = "";
  n = strlen(src);
  if (n >= cap) n = cap - 1;
  /* 服务端提示语是中文，截断必须落在字符边界（见 pc_utf8_fit）。 */
  n = pc_utf8_fit(src, n);
  memcpy(dst, src, n);
  dst[n] = '\0';
}

/* 会话只需握手一次；失败不设状态，下次调用会重试（网络抖动不至于永久失效）。
 *
 * 加锁的原因：登录 / 注册 / 充值 / 公告各跑在独立线程里，两个线程可能同时
 * 看到 booted==0 → 并发握手，互相覆盖会话串；也可能在 bootstrap 写 sessl
 * 的同时另一个线程正在读它（撕裂读 → 请求带半截会话串 → 服务端回「未登录」）。
 * 表现就是「偶尔、无规律地验证失败」。锁覆盖「判断 + 握手」整段，
 * 保证同一时刻只有一个线程在握手。 */
/* 握手锁改为全进程唯一（定义在 pigeon_core.c 的导出层）。
 *
 * 早先这把锁是 pc_auth.c 的 static，只有「登录 / 注册 / 充值 / 公告」这条路
 * 拿它；心跳自愈（pc_bsphp.c 的 hb_loop）直接调 bootstrap，完全不持锁 ——
 * 于是两轮握手可以并发、各建一条匿名会话互相覆盖，而 reset() 的清零也会被
 * 心跳那一轮的写入反向覆盖，「会话自愈」永久失效。
 *
 * 现在锁只有一把，pc_bsphp_bootstrap_serialized() 与这里的 ensure / reset
 * 用的都是它。 */
void pc_boot_lock_acquire(void);
void pc_boot_lock_release(void);

/* 握手是否已完成。提到文件作用域（原先是 ensure 里的 static 局部量），
   好让「会话自愈」能从别处把它重置为 0。读写都在全局握手锁内。 */
static int g_booted = 0;

static int32_t pc_auth_bsphp_ensure(void) {
  int32_t rc;

  pc_boot_lock_acquire();
  if (g_booted) {
    pc_boot_lock_release();
    return PC_OK;
  }
  rc = pc_bsphp_bootstrap();
  if (rc == PC_OK) g_booted = 1;
  pc_boot_lock_release();
  return rc;
}

/* 会话自愈：把握手状态清零，让下一次业务调用重新 bootstrap 拿新会话串。
 *
 * 触发条件：某次业务响应的 code 命中「会话已死」白名单（pc_bsphp_session_dead）
 * —— 服务端认为当前会话已无效（超时 / 异地登录 / 被顶号等）。若不清零，
 *
 * 【必须连会话串一起清】原实现只把 g_booted 置 0，g_bs.sessl 里那条已死的登录
 * 会话原封不动留着。后果是「重新验证后仍带旧会话」：用户重新登录时，登录接口
 * 之前的任何一次调用（公告 / 充值）都会带着旧会话发出去，服务端继续回 1046 /
 * 1047 / 1049；而心跳线程拿到的也还是这条旧会话。清了才是真的重新开始。 */
static void pc_auth_bsphp_reset(void) {
  pc_boot_lock_acquire();
  g_booted = 0;
  /* 与 g_booted 一起清，两者必须一致：握手标志说「没握手」，
     会话串却还是旧的，就是自愈失效的根因。 */
  pc_bsphp_clear_session();
  pc_boot_lock_release();
}

/* BSPHP 成败判定：一律以响应 JSON 里的 code 查状态码表（表在 pc_bsphp.c）。
 *
 * 不再按中文关键词猜 —— 关键词会误伤，例如「帐号没有到期！」里含「到期」却
 * 其实是正常状态，而「2次密码输入不一致」这类也不该靠子串匹配。 */
static int pc_auth_bsphp_ok(const char* json) {
  int code = 0;

  if (pc_bsphp_json_int(json, "code", &code)) {
    int ok = pc_bsphp_code_ok(code);
    if (ok >= 0) return ok;
    /* 表里没有这个码：按失败处理（宁可挡住也不放行），并把码打进日志方便补表。 */
    pc_log("[验证] 未知状态码 code=%d，按失败处理", code);
    pc_log_flush();
    return 0;
  }

  /* 响应里根本没有 code 字段：无法判定为成功，一律按失败处理（fail-closed）。
     这是登录门禁 —— 早先这里回落到「不含中文失败关键词就判成功」，等于给
     任何没有 code 的响应（错误页、被劫持的响应、接口改版）开了后门。
     宁可挡住也不放行，并把原文摘要打进日志方便定位。 */
  pc_log("[验证] 响应缺少 code 字段，按失败处理");
  pc_log_flush();
  return 0;
}

/* 取给用户看的提示语：msg → 状态码原文 → （仅失败时）data → 通用兜底。
 *
 * 刻意**不再**把整段解密 JSON 当提示语：既难看，也会把 Token 之类的内部字段
 * 显示到界面上。成功且既无 msg 也无表内码文时给一句通用文案即可。 */
static void pc_auth_bsphp_msg(const char* json, int ok, char* out, size_t cap) {
  int code = 0;

  if (pc_bsphp_json_field(json, "msg", out, cap) && out[0] != '\0') return;
  if (pc_bsphp_json_int(json, "code", &code)) {
    const char* text = pc_bsphp_code_text(code);
    if (text != NULL) {
      pc_auth_copy(out, cap, text);
      return;
    }
  }
  /* data 只在失败时兜底：成功时它就是 Token，不该当提示语显示。 */
  if (!ok && pc_bsphp_json_field(json, "data", out, cap) && out[0] != '\0') {
    return;
  }
  pc_auth_copy(out, cap, ok ? "操作成功" : "验证未通过，请稍后重试");
}

/* 握手失败的提示语：网络没走通与握手被服务端拒绝，给的引导不一样。 */
static void pc_auth_boot_msg(int32_t rc, char* out, size_t cap) {
  pc_auth_copy(out, cap, rc == PC_ERR_NETWORK ? "网络连接失败，请检查网络后重试"
                                              : "网络验证握手失败，请稍后重试");
}

/* 把一次 BSPHP 调用的结果写进 pc_auth_result。
 *
 * call_rc 已经区分了「网络没走通」(-14) 与「服务端/协议失败」(-15)，这里据此
 * 给不同的引导文案 —— 前者提示重试，后者提示核对信息。 */
static int32_t pc_auth_bsphp_done(int32_t call_rc, const char* api,
                                  const char* json, pc_auth_result* out) {
  if (call_rc != PC_OK) {
    out->status = call_rc;
    if (call_rc == PC_ERR_NETWORK) {
      pc_auth_copy(out->message, sizeof(out->message),
                   "网络连接失败，请检查网络后重试");
    } else {
      pc_auth_copy(out->message, sizeof(out->message), "验证请求失败，请稍后重试");
    }
    /* 表单本身是通过的，问题出在网络：pc_result_reset 已把各槽位置为 OK。 */
    return call_rc;
  }
  {
    int ok = pc_auth_bsphp_ok(json);
    int code = 0;
    pc_bsphp_json_field(json, "data", out->data, sizeof(out->data));
    pc_auth_bsphp_msg(json, ok, out->message, sizeof(out->message));
    out->status = ok ? PC_OK : PC_ERR_SERVER;
    /* 业务成功时采用响应里的新会话串（SeSsL）——
       timeout.lg 用的就是它。
       注意必须把 api 传下去：只有 login.lg / chong.lg 这类真正建立登录态的
       接口才允许写会话；卡注册（registrationaska.lg）回的是匿名串，
       无差别采用会顶掉登录会话 → 心跳 1049。 */
    if (ok) {
      pc_bsphp_adopt_session_ex(api, json);
    }
    /* 会话自愈：响应 code 命中「会话已死」白名单（超时/异地登录/被顶号等）时，
       把握手状态清零，下次业务调用会重新 bootstrap 拿新会话串。不清零的话，
       g_booted 永远是 1，之后所有请求都带着这条死会话串，只能重启进程才恢复。 */
    if (pc_bsphp_json_int(json, "code", &code) &&
        pc_bsphp_session_dead(code)) {
      pc_log("[验证] 会话失效 code=%d，重置握手（下次调用重握）", code);
      pc_log_flush();
      pc_auth_bsphp_reset();
    }
    return out->status;
  }
}

int32_t pc_auth_login_impl(const char* user, const char* pwd,
                           pc_auth_result* out) {
  pc_slice u;
  pc_slice p;
  char user_buf[PC_ARG_BUF];
  char mac[40];
  char json[8192];
  int32_t rc;

  pc_result_reset(out);

  u = pc_trim(user);
  p = pc_slice_of(pwd);

  if (!pc_form_login(&u, &p, &out->form)) {
    out->status = PC_ERR_FORM;
    return PC_ERR_FORM;
  }

  pc_slice_to_buf(&u, user_buf, sizeof(user_buf));
  /* 机器码沿用 pc_authnet 的生成方式（注册表 MachineGuid → 卷序列号 → 兜底），
     BSPHP 的 key / maxoror 都传它。 */
  pc_authnet_machine_code(mac, sizeof(mac));

  rc = pc_auth_bsphp_ensure();
  if (rc != PC_OK) {
    out->status = rc;
    pc_auth_boot_msg(rc, out->message, sizeof(out->message));
    return rc;
  }

  json[0] = '\0';
  rc = pc_bsphp_login(user_buf, p.ptr, mac, json, sizeof(json));
  return pc_auth_bsphp_done(rc, "login.lg", json, out);
}

int32_t pc_auth_register_impl(const char* user, const char* pwd,
                              const char* pwd2, const char* card,
                              pc_auth_result* out) {
  pc_slice u;
  pc_slice p;
  pc_slice p2;
  pc_slice c;
  char user_buf[PC_ARG_BUF];
  char card_buf[PC_ARG_BUF];
  char mac[40];
  char json[8192];
  int32_t rc;

  pc_result_reset(out);

  u = pc_trim(user);
  p = pc_slice_of(pwd);
  p2 = pc_slice_of(pwd2);
  c = pc_trim(card);

  if (!pc_form_register(&u, &p, &p2, &c, &out->form)) {
    out->status = PC_ERR_FORM;
    return PC_ERR_FORM;
  }

  pc_slice_to_buf(&u, user_buf, sizeof(user_buf));
  pc_slice_to_buf(&c, card_buf, sizeof(card_buf));
  pc_authnet_machine_code(mac, sizeof(mac));

  rc = pc_auth_bsphp_ensure();
  if (rc != PC_OK) {
    out->status = rc;
    pc_auth_boot_msg(rc, out->message, sizeof(out->message));
    return rc;
  }

  /* BSPHP 的卡注册：kaid=卡号/激活码（界面那一栏「卡密」），kapwd 留空。 */
  json[0] = '\0';
  rc = pc_bsphp_register_by_card(user_buf, p.ptr, card_buf, mac, json,
                                 sizeof(json));
  return pc_auth_bsphp_done(rc, "registrationaska.lg", json, out);
}

int32_t pc_auth_recharge_impl(const char* user, const char* confirm,
                              const char* card, pc_auth_result* out) {
  pc_slice u;
  pc_slice cf;
  pc_slice k;
  char user_buf[PC_ARG_BUF];
  char pwd_buf[PC_ARG_BUF];
  char card_buf[PC_ARG_BUF];
  char json[8192];
  int32_t rc;

  pc_result_reset(out);

  u = pc_trim(user);
  /* 第二栏是密码，同样不 trim。 */
  cf = pc_slice_of(confirm);
  k = pc_trim(card);

  if (!pc_form_recharge(&u, &cf, &k, &out->form)) {
    out->status = PC_ERR_FORM;
    return PC_ERR_FORM;
  }

  pc_slice_to_buf(&u, user_buf, sizeof(user_buf));
  pc_slice_to_buf(&cf, pwd_buf, sizeof(pwd_buf));
  pc_slice_to_buf(&k, card_buf, sizeof(card_buf));

  rc = pc_auth_bsphp_ensure();
  if (rc != PC_OK) {
    out->status = rc;
    pc_auth_boot_msg(rc, out->message, sizeof(out->message));
    return rc;
  }

  /* BSPHP 的充值 / VIP 续期：userset=1，ka=卡号，userpwd=账号密码。
     userpwd 是必填的 —— 实测传空串服务端回 code=1009「密码错误」。 */
  json[0] = '\0';
  rc = pc_bsphp_pay(user_buf, pwd_buf, card_buf, json, sizeof(json));
  return pc_auth_bsphp_done(rc, "chong.lg", json, out);
}

/* 公告正文里的 HTML 换行标签换成 \n（BSPHP 后台的公告常带 <br> / <br/>）。 */
static void pc_notice_br_to_nl(char* s) {
  size_t i = 0, j = 0, n = strlen(s);
  while (i < n) {
    if (s[i] == '<' && i + 3 <= n && (s[i + 1] == 'b' || s[i + 1] == 'B') &&
        (s[i + 2] == 'r' || s[i + 2] == 'R')) {
      size_t k = i;
      while (k < n && s[k] != '>') k++;
      if (k < n) {
        s[j++] = '\n';
        i = k + 1;
        continue;
      }
    }
    s[j++] = s[i++];
  }
  s[j] = '\0';
}

/* 系统公告：改用 BSPHP 的 gg.in，取到后逐条输出到运行日志。 */
int32_t pc_auth_notice_impl(void) {
  char json[8192];
  char body[8192];
  int32_t rc;

  json[0] = '\0';
  rc = pc_auth_bsphp_ensure();
  if (rc != PC_OK) {
    pc_log("[公告] 获取失败");
    pc_log_flush();
    return rc;
  }

  rc = pc_bsphp_notice(json, sizeof(json));
  if (rc != PC_OK) {
    pc_log("[公告] 获取失败");
    pc_log_flush();
    return rc;
  }

  body[0] = '\0';
  if (!pc_bsphp_json_field(json, "data", body, sizeof(body)) ||
      body[0] == '\0') {
    pc_bsphp_json_field(json, "msg", body, sizeof(body));
  }

  if (body[0] != '\0') {
    /* pc_to_utf8 负责把公告统一成 UTF-8：已是合法 UTF-8 则原样透传，否则按
     * ANSI/GBK -> UTF-8 转码（修复 GBK 公告在 CP_UTF8 控制台下乱码）。 */
    char utf8[8192];
    char* line;
    pc_notice_br_to_nl(body);
    pc_to_utf8(body, utf8, sizeof(utf8));

    pc_log("========== 系统公告 ==========");
    line = utf8;
    for (;;) {
      char* nl = strchr(line, '\n');
      if (nl != NULL) *nl = '\0';
      pc_log("%s", line);
      if (nl == NULL) break;
      line = nl + 1;
    }
    pc_log("============================================");
  }

  /* 公告是用户要立刻看到的关键日志：pc_log 是行缓冲批处理（200ms 超时刷新只
   * 在「下一条日志到来」时才会被评估），若写完后不再有日志输出，公告会一直卡在
   * 缓冲里直到下一条日志才被带出。这里显式 flush，确保公告第一时间显示。 */
  pc_log_flush();
  return PC_OK;
}
