/* ---------------------------------------------------------------------------
 * pc_bsphp.h 的实现。
 *
 * 逐段对应 BSPHP-C-DEMO-LOGIN：
 *   bs_md5_hex / bs_aes_* / bs_rsa_*   ← bsphp_crypto.c
 *   bs_send                            ← bsphp_client.c 的 bsphp_send_raw()
 *   pc_bsphp_bootstrap                 ← bsphp_bootstrap()
 *   pc_bsphp_login                     ← bsphp_login_lg()
 *   pc_bsphp_register_by_card          ← demo_register_by_card()
 *   pc_bsphp_pay                       ← bsphp_pay_lg()
 *   pc_bsphp_notice                    ← bsphp_get_notice()
 *
 * 加密原语用的是本仓已有的一套（BCrypt + CAPI，与 pc_shide.c 同源），不额外
 * 引入第三方库；HTTP 走 pc_http（WinHTTP）。
 *
 * 非 Windows 为空实现，保证核心包在别的平台仍可编译。
 * ------------------------------------------------------------------------- */

#include "pc_bsphp.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "pigeon_core.h" /* pc_core_shutdown：心跳 FATAL 走统一收尾路径 */
#include "pc_http.h"
#include "pc_log.h"

/* ---------------------------------------------------------------------------
 * BSPHP 状态码表（平台无关，纯数据）
 *
 * 服务端在响应 JSON 的 code 字段里回这些码。判定成功与否一律以此表为准，
 * 不再靠中文关键词猜 —— 关键词会误伤（例如"未到期"里含"到期"却被判失败）。
 * ok=1 的码在业务上表示"这一步做成了"。
 * ------------------------------------------------------------------------- */

typedef struct {
  int code;
  const char* text;
  int ok;
} bs_code_t;

static const bs_code_t k_bsphp_codes[] = {
    /* 实测：internet.in / gg.in 返回 code=200 表示成功（通用 OK），官方表未收录。
     * 注意 code 的含义随接口而异：握手用的 200/1000 与业务码表不是一套。 */
    {200, "执行成功", 1},

    {1000, "用户已经存在。请选择其他!", 0},
    {1001, "你选择用户名可以使用!", 1},
    {1002, "2次密码输入不一致!", 0},
    {1003, "账号长度错误限制 3-15位", 0},
    {1004, "账号格式错误,只能选择中文/ 26位字母+数字和_下滑线", 0},
    {1005, "恭喜你注册成功!", 1},
    {1006, "账号注册失败,你要注册账号可能被抢注了.", 0},
    {1007, "密码长度限制 3-15位数", 0},
    {1008, "账号错误", 0},
    {1009, "密码错误", 0},
    {1010, "登陆账号不存在", 0},
    {1011, "登陆成功", 1},
    {1012, "密码错误", 0},
    {1013, "登陆失败", 0},
    {1014, "QQ号错误", 0},
    {1015, "邮箱错误", 0},
    {1016, "手机号码错误", 0},
    {1017, "保存成功", 1},
    {1018, "保存失败", 0},
    {1019, "不能输入空格", 0},
    {1020, "请输入密保问题或者答案", 0},
    {1021, "账号已经被冻结禁止登陆", 0},
    {1022, "记录查询失败", 0},
    {1023, "你的密保信息已经填写", 1},
    {1024, "密保信息添加成功", 1},
    {1025, "密保添加失败", 0},
    {1026, "密码不能包含空格", 0},
    {1027, "请输入旧密码", 0},
    {1028, "旧密码不能和新密码一致", 0},
    {1029, "密码修改失败", 0},
    {1030, "旧密码不正确,请重新输入", 0},
    {1031, "密码修改成功", 1},
    {1032, "表单信息不能为空,请返回填写", 0},
    {1033, "密码已经成功通过密保信息修改", 1},
    {1034, "密保信息错误", 0},
    {1035, "密码找回失败", 0},
    {1036, "验证码不能为空", 0},
    {1037, "验证码正确", 1},
    {1038, "验证码错误", 0},
    {1039, "检测账号不能为空", 0},
    {1040, "账号不能包含空格", 0},
    {1041, "长时空闲超时执行正常", 1},
    {1042, "长时空闲超时执行异常", 0},
    {1043, "账号不存在", 0},
    {1044, "账号已经被冻结禁止登陆", 0},
    {1045, "登陆超时,由于你长时间不停留请重新登陆", 0},
    {1046, "你在别处已经登陆,被迫登出！", 0},
    {1047, "已经登陆", 0},
    {1048, "你需要登陆才可以访问", 0},
    {1049, "未登录,需要登录后再调用,请传递登录后的SeSsL串再继续操作.", 0},
    {1050, "密保不能少于4字符", 0},
    {1051, "密保信息未填写", 0},
    {1052, "充值账号不能为空", 0},
    {1053, "充值卡号不能为空", 0},
    {1054, "充值卡密码不能为空", 0},
    {1055, "充值账号不能包含空格", 0},
    {1056, "充值卡号不能包含空格", 0},
    {1057, "充值卡密码不能包含空格", 0},
    {1058, "充值卡号或充值卡密码错误", 0},
    {1059, "充值的用户账号不存在", 0},
    {1060, "充值卡账号密码错误或者不存在", 0},
    {1061, "用户没有使用过要充值软件,拒绝充值", 0},
    {1062, "激活成功,赶快去使用吧!", 1},
    {1063, "充值失败!", 0},
    {1064, "充值卡已经充值过了", 0},
    {1065, "你留言和反馈我们已经收到,谢谢你的支持", 1},
    {1066, "提交留言失败", 0},
    {1067, "请输入标题", 0},
    {1068, "请输入留言内容", 0},
    {1069, "激活成功,请在次验证就可以使用了！", 1},
    {1070, "添加失败", 0},
    {1071, "糟糕卡串已经存在了", 0},
    {1072, "还没有存在", 0},
    {1073, "卡串不存在或者错误", 0},
    {1074, "你使用激活串已到期作废！", 0},
    {1075, "卡串已经存在,无法激活", 0},
    {1076, "car执行错误", 0},
    {1077, "请检查卡串号或者密码错误！", 0},
    {1078, "你使用权已经被冻结,无法验证！", 0},
    {1079, "验证失败请重新验证,或是否已经登陆（BSphpSeSsL超时）", 0},
    {1080, "验证成功", 1},
    {1081, "登录验证成功！", 1},
    {1082, "你的使用期已到,请购卡在使用", 0},
    {1083, "没有查询到用户信息", 0},
    {1084, "该用户不是使用本软件的", 0},
    {1085, "用户已经被冻结", 0},
    {1086, "卡串或者验证串已经被冻结,无法继续。", 0},
    {1087, "帐号已经到期请充值在使用。", 0},
    {1088, "请输入一个邮箱作为你的帐号", 0},
    {1089, "恭喜你注册成功,赶快去你邮箱把你帐号激活吧!", 1},
    {1090, "密保邮箱不能为空!", 0},
    {1091, "密保邮箱格式不正确,请重新输入!", 0},
    {1092, "QQ号不能为空!", 0},
    {1093, "QQ号格式输入不正确,请重新输入!", 0},
    {1094, "你的帐号还没激活,现在已经有一封激活邮件发到你注册邮箱上", 0},
    {1095, "请输入你联系访方式 QQ/邮箱/电话", 0},
    {1096, "账号余额不足,无法继续。", 0},
    {1097, "账号余额不足,请充值在继续。", 0},
    {1098, "执行扣点成功。", 1},
    {1099, "执行扣点失败。", 0},
    {1100, "扣除金额不能为零或小于零。", 0},
    {1101, "账号扣点为Bsphp验证商业功能才扣除", 0},

    {1119, "当前软件是账号登录模式,需要账号登录限时模式下软件使用", 0},

    /* ---- 负数码：官方状态码表未收录，来自实测 ----
     * login.lg 在「账号密码正确、但本机还没绑定」时返回 -3。
     * 按失败处理（绑定未完成 = 不能放行）；若你的后台把它当可放行，改这里的 0 即可。 */
    {-3, "还没有绑定,请绑定在登录", 0},

    {5000, "无法接收到GET数据包", 0},
    {5001, "无法接收到POST数据包", 0},
    {5002, "数据包内出现系统屏蔽字符串", 0},
    {5003, "数据包已经过期,拒绝接收", 0},
    {5004, "接口不存在,连接失败", 0},
    {5005, "软件连接号错误,访问软件不存在", 0},
    {5006, "软件MD5验证失败", 0},
    {5007, "非法的请求,身份验证失败!", 0},
    {5008, "欢迎你首次使用!,请重新登陆.", 0},
    {5009, "绑定特征码,已经有人绑定过了,不能重复绑定,不能登陆", 0},
    {5010, "当前绑定特征已经有人绑定了", 0},
    {5011, "账号注册成功,当前机器特征已经有人绑定", 0},
    {5012, "当前特征已经有人绑定,无法在绑定", 0},
    {5013, "绑定成功!", 1},
    {5014, "绑定失败,请重试!", 0},
    {5015, "绑定特征不能为空", 0},
    {5016, "已经绑定了,不需要在绑定", 1},
    {5017, "使用软件不属于登陆模式", 0},
    {5018, "当前卡串已经到期,无法解除绑定", 0},
    {5019, "解除绑定将到期,无法解除绑定", 0},
    {5020, "解除绑定失败,请重试或者联系相关人员解决", 0},
    {5021, "解除绑定成功,已经扣除对应时间", 1},
    {5022, "当前的卡串已经解除绑定,无须在解除绑定", 0},
    {5023, "绑定KEY不能为空", 0},
    {5024, "恭喜你!绑定成功", 1},
    {5025, "绑定失败,当前卡串已经绑定key,必须解除绑定才能在绑定", 0},
    {5026, "账号登录超时,由于你长时间没有操作请种新登录", 0},
    {5027, "登录状态更新失败！", 0},
    {5028, "登录状态更新成功！", 1},
    /* 「帐号没有到期！」= 账号正常未过期，属于**成功**。
       早先误标成失败：官方表里这句提示出现在「到期检查」接口，
       语义是「（检查结果）账号还没到期」。 */
    {5029, "帐号没有到期！", 1},
    {5030, "登录帐号已经到期！", 0},
    {5031, "执行正常", 1},
    {5032, "扣点模式之扣点执行失败", 0},
    {5033, "用户已经到期,无法获取重要的验证数据", 0},
    {5034, "非绑定机器 取重要验证数据加验证绑定特征", 0},
    {5035, "非绑定机器 登录时候验证绑定特征", 0},
    {5036, "执行正常,当前扣点模式为：客户端扣点API调用被动", 1},
    {5037, "登录模式计点模式扣点执行正常", 1},
    {5038, "登录模式计点模式扣点执行失败", 0},
    {5039, "扣点点数不能小于或者等于0", 0},
    {5040, "模式不匹配,当前API只能在《登录计时模式》下使用", 0},
    /* 5041 官方表里出现两次（两种模式的提示），这里合并为一条。 */
    {5041, "软件非扣点模式,API无法执行 / 使用软件不属于卡串计时、扣点模式", 0},
    {5043, "模式不匹配,当前API只能在《卡串计时模式》下使用", 0},
    {5044, "点数不足,无法扣除！", 0},
    {5045, "模式不匹配,当前API只能在《登录扣点模式》下使用", 0},
    {5046, "模式不匹配,当前API只能在《卡串扣点模式》下使用", 0},
    {5047, "登录限制验证通过,登录继续！", 1},
    {5048, "当前机器登陆在线量已经到达上限", 0},
    {5049, "机器同时登录在线使用数量已经达到上限", 0},
    {5050, "账号同时登录在线数量已经到上限", 0},
    {5051, "机器标记没有不可空", 0},
    {5052, "Sgin签名验证失败", 0},
    {5053, "Sgin签名参数不能为空", 0},
    {5054, "无法识别的通信方式", 0},
    {5055, "当前激活码已经被冻结禁止登录当前软件", 0},
    {5056, "多开控制无法获取用户信息", 0},
    {5057, "模式不匹配,当前API只能在《账号登录限时模式》下使用", 0},
    {5058, "模式不匹配,当前API只能在《卡串验证限时模式》下使用", 0},

    {9980, "用户VIP到期", 0},
    {9908, "用户VIP到期", 0},
    {9981, "绑定特征码等于空,未绑定", 0},
};

static const bs_code_t* bs_code_find(int code) {
  size_t i;
  for (i = 0; i < sizeof(k_bsphp_codes) / sizeof(k_bsphp_codes[0]); i++) {
    if (k_bsphp_codes[i].code == code) return &k_bsphp_codes[i];
  }
  return NULL;
}

int pc_bsphp_code_ok(int code) {
  const bs_code_t* e = bs_code_find(code);
  return (e == NULL) ? -1 : e->ok;
}

const char* pc_bsphp_code_text(int code) {
  const bs_code_t* e = bs_code_find(code);
  return (e == NULL) ? NULL : e->text;
}

/* 心跳失败三级分类 —— 心跳门禁专用，**不是**通用成败判定。
 *
 * 为什么不直接用 pc_bsphp_code_ok() == 0：那张码表是「业务结果表」，把所有
 * 失败都标 ok=0，其中大量是**可继续运行**的失败（密码错误、卡串错误、扣点
 * 失败、参数不合法……）。更关键的是 code 的含义**随接口而异**：同一个 1000
 * 在业务码表里是「用户已存在」的失败，在 BSphpSeSsL.in 握手响应里却是正常码。
 * 拿整张表当心跳门禁，会把正常心跳误判成会话失效而杀掉整个应用（自杀）。
 *
 * 旧实现只有「杀 / 不杀」二元判断，把下面三类完全不同的情况混成一条线：
 *
 *   (a) 真·授权失效 —— 冻结 / 到期 / 被顶号 / 账号级超时。
 *       继续跑没有任何意义，服务端也不会再放行，必须结束进程。
 *   (b) 本地会话问题 —— 1049「未登录」/ 5027「登录状态更新失败」。
 *       前者几乎总是客户端把会话串弄丢或覆盖了（见 bs_api_may_adopt_session
 *       的注释），重新握手就能恢复；后者是服务端一次写库失败，下轮就好。
 *       把它们当致命 → 一次本地小故障就杀掉整个程序。
 *   (c) 网络 / 协议层失败 —— 断网、超时、响应解不开、缺 code、表外未知码。
 *       这类**根本没有服务端结论**，更没有理由终止。
 *
 * 所以改成三级：OK / TRANSIENT（可自愈，绝不终止）/ FATAL（才终止）。 */

/* 分级对应的中文说明（日志与界面提示共用）。 */
const char* pc_bsphp_hb_class_text(int level) {
  switch (level) {
    case PC_HB_OK:
      return "正常";
    case PC_HB_TRANSIENT:
      return "可恢复（不终止）";
    case PC_HB_FATAL:
      return "授权失效（终止）";
    default:
      return "未知";
  }
}

/* 单个业务码的分级。只有 FATAL 白名单会终止进程。 */
static int bs_code_level(int code) {
  switch (code) {
    /* ---- FATAL：账号 / 授权已经不可用，继续跑无意义 ---- */

    /* 冻结 / 禁止登陆 */
    case 1021:
    case 1044:
    case 1078:
    case 1085:
    case 1086:
    case 5055:
    /* 到期 / VIP 到期 */
    case 1074:
    case 1082:
    case 1087:
    case 9980:
    case 9908:
    case 5030:
    /* 账号级超时 / 被迫登出（不是本地会话丢失，是服务端已经踢了） */
    case 1045:
    case 1046:
    case 5026:
    /* 在线数超限：机器/账号的在线名额已经用满，服务端不会再放行。
       继续跑没有意义 —— 重握手、重试都换不来一个名额，只会空转。
       按授权失效处理，让用户明确知道要去关掉多开的实例。 */
    case 5048:
    case 5049:
    case 5050:
      return PC_HB_FATAL;

    /* ---- TRANSIENT：本地会话问题 / 服务端瞬时失败，重握手或下轮可自愈 ---- */

    /* 1049「未登录」：心跳拿到的会话串不是登录态。绝大多数情况是客户端
       自己把会话串覆盖/清空了（公告走匿名 session、bootstrap 空窗期等），
       重新握手 + 重新登录即可恢复。**不是账号问题，绝不能杀进程。** */
    case 1049:
    /* 5027「登录状态更新失败！」：服务端一次写库失败，下一轮就能成功。 */
    case 5027:
      return PC_HB_TRANSIENT;

    default:
      /* 成功码、可继续运行的业务失败码、表外未知码 —— 一律不终止。 */
      return PC_HB_OK;
  }
}

int pc_bsphp_hb_classify(int32_t call_rc, const char* json) {
  int code = 0;
  int level;

  /* 1) 网络 / 协议层失败：根本没有服务端结论，绝不终止。
        （断网、超时、TLS 失败、组包失败、响应解不开都在这里） */
  if (call_rc != PC_OK) return PC_HB_TRANSIENT;

  /* 2) 响应里没有 code：无法判定。fail-open 到这里是有意的 ——
        心跳是「保活」，不是「登录门禁」。登录门禁在 pc_auth_bsphp_ok()
        里 fail-closed；这里若也 fail-closed，等于任何异常响应都杀程序。 */
  if (json == NULL || !pc_bsphp_json_int(json, "code", &code)) {
    return PC_HB_TRANSIENT;
  }

  level = bs_code_level(code);

  /* 3) 成功码：确认正常。 */
  if (level == PC_HB_OK && pc_bsphp_code_ok(code) == 1) return PC_HB_OK;

  return level;
}

/* 兼容旧符号：「会话是否已死」= 分级是否为 FATAL。
 *
 * 保留这个函数只为不破坏既有调用方（pc_auth.c 的会话自愈也在用它判断
 * 「这条会话还能不能用」）。注意它的语义已经收窄：1049 / 5027 / 5048-5050
 * 不再算「死」，因为重新握手就能恢复。 */
int pc_bsphp_session_dead(int code) {
  return bs_code_level(code) == PC_HB_FATAL ? 1 : 0;
}

/* 定位对象成员 "key"，返回冒号之后第一个非空白字符；找不到返回 NULL。
 *
 * 比简单的 strstr("\"key\":") 稳两点：
 *   1. 容忍 "key" : 值 这种带空白的写法（后台换个序列化风格就取不到了）；
 *   2. 只认对象成员名 —— 要求它前面是 { 或 ,，避免某个字符串值的内容里恰好
 *      出现 "code": 时取错字段（例如提示语里带了这样的片段）。 */
static const char* bs_json_seek(const char* json, const char* key) {
  char pattern[160];
  size_t plen;
  const char* p;

  if (json == NULL || key == NULL) return NULL;
  snprintf(pattern, sizeof(pattern), "\"%s\"", key);
  plen = strlen(pattern);

  p = json;
  while ((p = strstr(p, pattern)) != NULL) {
    const char* b = p;
    const char* q;
    /* 往前跳过空白，确认这个引号是「对象成员名」的开头。 */
    while (b > json && (b[-1] == ' ' || b[-1] == '\t' || b[-1] == '\r' ||
                        b[-1] == '\n')) {
      b--;
    }
    if (b == json || b[-1] == '{' || b[-1] == ',') {
      q = p + plen;
      while (*q == ' ' || *q == '\t' || *q == '\r' || *q == '\n') q++;
      if (*q == ':') {
        q++;
        while (*q == ' ' || *q == '\t' || *q == '\r' || *q == '\n') q++;
        return q;
      }
    }
    p += plen;
  }
  return NULL;
}

/* 从 key 处起读一个字符串值，返回起始/结束指针（不含引号）。
   字符串里的 \" 这类转义按「一对」跳过，不会提前把值截断。 */
static int bs_json_string_span(const char* p, const char** begin,
                               const char** end) {
  const char* q;

  if (p == NULL || *p != '"') return 0;
  p++;
  q = p;
  while (*q != '\0') {
    if (*q == '\\' && q[1] != '\0') {
      q += 2;
      continue;
    }
    if (*q == '"') break;
    q++;
  }
  if (*q != '"') return 0;
  *begin = p;
  *end = q;
  return 1;
}

/* JSON 取值：兼容 "key":123 与 "key":"123"。
 *
 * 【这里只负责「把值切成一段文本」，不做任何类型校验】
 * 它同时服务两个调用方：
 *   · pc_bsphp_json_int   —— 要数字，自己做数字校验；
 *   · pc_bsphp_json_field —— 要字符串（data / msg / SeSsL 等），
 *                            这些值绝大多数**不是数字**。
 * 早先有人把「必须是数字」的校验写进了这个通用函数，结果 json_field
 * 取不到任何非数字字符串 —— bootstrap 拿不到会话串，登录直接报
 * 「网络验证握手失败」。数字校验必须留在 pc_bsphp_json_int 里。 */
static int bs_json_value(const char* json, const char* key,
                         const char** begin, const char** end) {
  const char* p = bs_json_seek(json, key);
  const char* q;

  if (p == NULL) return 0;
  if (*p == '"') {
    return bs_json_string_span(p, begin, end);
  }
  /* 数字，可能带负号：实测 login.lg 会返回 code:-3。 */
  q = p;
  if (*q == '-') q++;
  while (*q >= '0' && *q <= '9') q++;
  if (q == p || (q == p + 1 && *p == '-')) return 0;
  *begin = p;
  *end = q;
  return 1;
}

int pc_bsphp_json_int(const char* json, const char* key, int* out) {
  const char* b = NULL;
  const char* e = NULL;
  int v = 0;
  int neg = 0;

  if (out == NULL) return 0;
  if (!bs_json_value(json, key, &b, &e)) return 0;
  if (b < e && *b == '-') {
    neg = 1;
    b++;
  }
  /* 走到这里的 b..e 可能是「裸数字」也可能是「字符串里的数字」。两种都要
   * 逐字节校验并防溢出：
   *   · "code":"abc" 会算出 49（'a'-'0'）这种垃圾码 —— 而 code 是全部业务
   *     判定与心跳分级的唯一依据，垃圾码会让心跳门禁静默失效；
   *   · 有符号溢出是 UB，溢出后的值同样落进「表外码」分支。
   * 任何一个不满足就判「取不到」，调用方走 fail-closed / TRANSIENT。 */
  for (; b < e; b++) {
    int digit = *b - '0';
    if (digit < 0 || digit > 9) return 0;
    if (v > (2147483647 - digit) / 10) return 0;
    v = v * 10 + digit;
  }
  *out = neg ? -v : v;
  return 1;
}

#ifdef _WIN32

#include <windows.h>
#include <bcrypt.h>
#include <wincrypt.h>

/* AES（bcrypt）与 CAPI 的 RSA 公钥导入都要显式挂库。
 *
 * 原 snap 工程里这两行是 pc_shide.c 挂的 —— 那个文件不在本工程的移植范围内
 * （验证页只用到 BSPHP 认证），但 pc_bsphp.c 自己也在用 BCrypt* 与
 * CryptAcquireContext，所以必须在这里补上，否则链接期报一长串
 * 「无法解析的外部符号 BCryptOpenAlgorithmProvider」。
 *
 * 用 #pragma comment 而不是让 hook 传 link 参数：CMake 侧的 runner 也有
 * 同样的需求（那里只编 C++），让库依赖跟着源码走，两处都不用各自维护。 */
#pragma comment(lib, "bcrypt.lib")
#pragma comment(lib, "crypt32.lib")
#pragma comment(lib, "advapi32.lib")

/* ---------------------------------------------------------------------------
 * 配置：默认取自 DEMO 的 bsphp_config.h（接口地址 / 通信 key / 服务端私钥 /
 * 客户端公钥）。换自己的后台时，用 pc_bsphp_configure 覆盖，或直接改这里的宏。
 * ------------------------------------------------------------------------- */

#define BS_URL_DEFAULT "https://lzy.yue.mohuajz.eu.org/AppEn.php?appid=15446295&m=f1ff7a1930d23088b0cf0d1d95aa555e&lang=0"
#define BS_MUTUAL_KEY_DEFAULT "d309305099f24186f1e166d57a915b77"
#define BS_PRIV_DEFAULT "MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC9p8DhemXAdYr//ewYAzJm5CPp4Qb/StMTBZ40JRwMx8xhsbfN0tikYsHbUpBOxUIGRR4rYtyOyNkdYZImm8JFB8fCPwdIUtIAPBaqRq1HCXFizFn51QeB9YuVbKZ2ji+24FSsMhoEAO/ACwwniTzGh92+Y4uKJJvDrrGo1ET2pOQNheVe7TZYLzEkChI6Gr1NzYxyp+PvGckL4GVOjMrjdISHbf8ugqF392uxw+G+Fol4eo7V4cLmKpjktVBPHrMjNpG0JMx9EofY/7IWDe4+34/+wrN+X4GXGIohGMwXmKGw1xSsblZorq2UnGJveCzJRQumi/W7THkaq1CWAvrHAgMBAAECggEBAI5GJkAAHgz/IMNhrZdl7o2ZYAe3tBQYAbgnYsMjg6Niz0QKmiRho/vNyjfJ/E/bUuh5OWS6yVKkAZw08frcpiQ67fQebEwpNTjP2wDp/FtqDhFb07PDx9oKZig2VbpieBDswRhcjX+rZC/hGcEfBuS4T/TfoHKFfASULNrGQuXzCCRCQfzlQnl6VjfQ+Nhb4U0fSVC1JzlJqG5YBefXAsASx/27/tJdS/ATYgp0uEZbaD68kVw8CxNDmKFuIZ1gAZKJLEQNw3r9J+857ff7Gk0d9hF0bRSnALCRPzwUo9ziYIQ08rUTEl+JIcElJXsZ3PWQAfvJrHBqcTWoxxSreaECgYEA9n0ggsrZUCbtRbKCVOuJ89hxEpYANG1XdFIGP29+niLJ4Pm81X+KPKLUf/z4FNQ3dYOZjxb0G6pMyDdHBw3rEcMTWIEBNh4UQSux+TDqdYP2HeuRUf1WYn2lXFj8Nl91gxcJtcIYvPSbiW+9pvOV+IeBDG2EV4y/96TqyquXuR0CgYEAxPk2TTE1v5ValPllqTi2hOL6LMF7bQf+GV2PT4yiGrhZHeVbs53eo19l2gjINCn7frYD2BsAsaF5PG/+cYStQILNZX68KB+MD0BCDV1P3ZRQ112kEZ9BycSwj4rl6TY4QL7jxEv3yrgvi1C4H7qfKF3w8lobV1AxOlS6mqHcYjMCgYAeZKVqmzqakII3UuCROg3jnG+s3AQgcs8Sz75negcB1sZP0FuBc92GxokvUvEAGH7SJaz8oNbuxlv7YB2I+CVhJk2vXxDYLHNQ6eNjF64BWYkyfUaI9pT9RgLq1SocRj8GMAQJfmpwejTniHi5KlX2tDasYqCr7vYIwjQVU3083QKBgDRKTGYVqEUh6xgdVSWlTp7cermi65c4RfaJ5d+iX+5j/hR3rO5z/IS2cJ1/M1bVxlQPEdou4PJHAZ5PxOZx6GR11P0ateyY41+xGVfe67LRCt0BmOqsspRTyONyZjKRGEHn6yNTX4bLeqOrXBXgPxxCRBKyZQu62Da6A4fFbHINAoGAQdsN3FgDCR6fLci9slvRNvFvPVlbZDHWAV38NfNdJc2dDCu2oNlC/0Xaf4W/sbPjUbfBztrlYUDDE2sTYwnz/Zmlutb15wjsx6N1oRIDkPGv00Qzv0Hik8AY9fLKSsrt14N5qCBERQiChG9DO3iZXyn6/Sr2TCFNR84Y1H/ohq8="
#define BS_PUB_DEFAULT "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEArS33RNWCUg0/KTfSXZg71SLr5jmf5xnlBWsCTMnZp4lLcp87qr7gMZkE+26WDwy4kXZ9p+M7PPPjES9bSsKtt78O/v2FuG+RMaivBWKpJa588t4HMxMlSlEiuqwpinVG5pswi9EE2NF/7ztirowVtzs+TTD6FiDvMgloKNiuVuND/tOd9Mth/9aOk9T2maTVDtjrj/+17c8YH4biKlq6TuYwQqMObwW1a7c5o2B1BYeNEsUve+QXFLNZGRVzjVeebv/las5xbME95JDrDoUF9s9YVwNTFOTM5o1H4Ekpu20iulEeZWHanvjc+vvK0kmKTTZWnHsFzFMAc8L5u3y44wIDAQAB"

#define BS_SIGN_TAIL "json"

/* 单次请求的超时（毫秒），与其它接口保持一致。 */
#define BS_CONNECT_MS 10000
#define BS_READ_MS 15000

typedef struct {
  char url[512];
  char mutual_key[128];
  char priv_b64[4096];
  char pub_b64[1024];
  char sessl[256];
} bs_cfg_t;

/* 静态初始化：这几个函数可能从不同的 isolate 线程进来，惰性初始化要加锁，
   而静态初始化天然没有这个竞态。configure 只在启动时调一次，运行期只读。 */
static bs_cfg_t g_bs = {BS_URL_DEFAULT, BS_MUTUAL_KEY_DEFAULT, BS_PRIV_DEFAULT,
                        BS_PUB_DEFAULT, ""};

/* 保护 g_bs.sessl（以及握手期间的写入）。
 *
 * 登录 / 注册 / 充值 / 公告各跑在独立线程里：一个线程在 bootstrap 里写 sessl，
 * 另一个线程可能正在 bs_send 里读它（撕裂读 → 请求带半截会话串 → 服务端回
 * 「未登录」），表现就是「偶尔、无规律地验证失败」。
 *
 * 只锁「读写 sessl」这一段；握手整体与否由 pc_auth.c 的 g_boot_lock 负责，
 * 保证同一时刻只有一个线程真正在握手。 */
static SRWLOCK g_sessl_lock = SRWLOCK_INIT;

/* 保护 g_bs 里除 sessl 之外的配置字段（url / mutual_key / priv_b64 / pub_b64）。
 *
 * 这几个字段是多字节字符串，configure 是「多字节写」、bs_send 是「多字节读」，
 * 没有锁时运行期调用 configure 会让对方读到半写内容（priv_b64 半写 → 导入 RSA
 * 失败或算出错误的 key）。当前 Dart 侧没有 configure 的绑定，属潜在问题；
 * 按「静态初始化 + 读写都加锁」补齐，代价可忽略（bs_send 每次调用只取一次快照）。 */
static SRWLOCK g_cfg_lock = SRWLOCK_INIT;

/* 配置快照：锁内一次性拷出，锁外使用。容量与 g_bs 对应字段一致。 */
typedef struct {
  char url[512];
  char mutual_key[128];
  char priv_b64[4096];
  char pub_b64[1024];
} bs_cfg_snapshot_t;

/* bs_copy 定义在下面的「小工具」一节，这里先声明（快照函数在它之前）。 */
static void bs_copy(char* dst, size_t cap, const char* src);

static void bs_cfg_snapshot(bs_cfg_snapshot_t* out) {
  AcquireSRWLockShared(&g_cfg_lock);
  bs_copy(out->url, sizeof(out->url), g_bs.url);
  bs_copy(out->mutual_key, sizeof(out->mutual_key), g_bs.mutual_key);
  bs_copy(out->priv_b64, sizeof(out->priv_b64), g_bs.priv_b64);
  bs_copy(out->pub_b64, sizeof(out->pub_b64), g_bs.pub_b64);
  ReleaseSRWLockShared(&g_cfg_lock);
}

/* ---------------------------------------------------------------------------
 * 小工具
 * ------------------------------------------------------------------------- */

/* 有界字符串拷贝（pc_authnet.c 里的 pc_copy_str 是它自己的 static，不能复用）。 */
static void bs_copy(char* dst, size_t cap, const char* src) {
  size_t n;
  if (dst == NULL || cap == 0) return;
  if (src == NULL) src = "";
  n = strlen(src);
  if (n >= cap) n = cap - 1;
  memcpy(dst, src, n);
  dst[n] = '\0';
}

/* 取一份会话串快照（调用方自己给缓冲，锁内拷贝，锁外使用）。 */
static void bs_sessl_snapshot(char* out, size_t cap) {
  AcquireSRWLockShared(&g_sessl_lock);
  bs_copy(out, cap, g_bs.sessl);
  ReleaseSRWLockShared(&g_sessl_lock);
}

/* 当前会话是否处于「登录态」。g_sessl_lock 保护。
 *
 * 为什么需要这个标志：全局只有一份 g_bs.sessl，却被三种语义写入 ——
 *   握手串（匿名）、登录串（带登录态）、业务响应回显串。
 * 服务端每次响应都回显 session_id()（见 bsphp_json.php），而 .in 接口走的是
 * 「新建匿名 session」分支，所以握手串**不带登录态**。它一旦顶掉登录会话，
 * 下一次 timeout.lg 必然被 Plug_User_Is_Login_Seesion() 判为「未登录(1049)」。
 * 有了这个标志，bootstrap 才知道「手上已有登录会话，不要拿匿名串覆盖」。 */
static int g_sessl_has_login = 0;

/* 覆盖会话串（空串 = 让旧会话失效）。is_login 表示这条会话是否带登录态。 */
static void bs_sessl_store_ex(const char* sessl, int is_login) {
  AcquireSRWLockExclusive(&g_sessl_lock);
  bs_copy(g_bs.sessl, sizeof(g_bs.sessl), sessl != NULL ? sessl : "");
  if (sessl == NULL || sessl[0] == '\0') {
    g_sessl_has_login = 0;
  } else if (is_login) {
    g_sessl_has_login = 1;
  }
  ReleaseSRWLockExclusive(&g_sessl_lock);
}

/* 原子地写入匿名会话：**仅当当前没有登录会话时**才写。
 *
 * 返回 1 = 已写入；0 = 已有登录会话，未覆盖。
 *
 * 为什么必须是原子操作：调用方（bootstrap）原本是「先读一次 g_sessl_has_login
 * 判断、else 分支再 store」，两步之间没有锁。窗口内 login.lg 一旦成功写入
 * 登录会话，这次 store 就把匿名握手串盖了上去 → timeout.lg 回 1049 →
 * 心跳判定异常。判断与写入必须在同一把锁内完成。 */
static int bs_sessl_store_anon_if_no_login(const char* sessl) {
  int wrote = 0;
  AcquireSRWLockExclusive(&g_sessl_lock);
  if (!g_sessl_has_login) {
    bs_copy(g_bs.sessl, sizeof(g_bs.sessl), sessl != NULL ? sessl : "");
    if (sessl == NULL || sessl[0] == '\0') {
      g_sessl_has_login = 0;
    }
    wrote = 1;
  }
  ReleaseSRWLockExclusive(&g_sessl_lock);
  return wrote;
}

/* 往 k=v&k=v 串里追加一个参数，**值做百分号编码**。
 *
 * 为什么必须编码：整串虽然最后会被 AES 加密，但服务端解密后仍按 '&' 拆参数。
 * 值里若含 '&' / '=' 就会凭空多出一个参数、或把值从中间切断 —— 用户看到的是
 * 「密码错误」这种莫名结论（本地校验明明通过了）。用户名有字符集限制、天然安全，
 * 但密码 / 卡密没有，所以一律走这里编码，不能直接 snprintf 拼。
 *
 * 编码字符集与 bs_url_encode 一致（字母数字与 - _ . ~ 之外全部 %XX），
 * 服务端按标准百分号解码即可还原。返回 0 成功，-1 表示缓冲不足。 */
static int bs_append_param(char* buf, size_t cap, const char* key,
                           const char* value) {
  size_t len = strlen(buf);
  size_t i;
  char* p = buf + len;

  if (len > 0) {
    if (len + 2 > cap) return -1;
    *p++ = '&';
    len++;
  }
  for (i = 0; key[i] != '\0'; i++) {
    if (len + 2 > cap) return -1;
    *p++ = key[i];
    len++;
  }
  if (len + 2 > cap) return -1;
  *p++ = '=';
  len++;

  for (i = 0; value[i] != '\0'; i++) {
    unsigned char c = (unsigned char)value[i];
    if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
        (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~') {
      if (len + 2 > cap) return -1;
      *p++ = (char)c;
      len++;
    } else {
      if (len + 4 > cap) return -1;
      snprintf(p, cap - len, "%%%02X", c);
      p += 3;
      len += 3;
    }
  }
  *p = '\0';
  return 0;
}

static int bs_b64_enc(const unsigned char* data, size_t len, char* out,
                      size_t cap) {
  DWORD cb = 0;
  if (!CryptBinaryToStringA(data, (DWORD)len,
                            CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, NULL,
                            &cb))
    return -1;
  if ((size_t)cb + 1 > cap) return -1;
  if (!CryptBinaryToStringA(data, (DWORD)len,
                            CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, out,
                            &cb))
    return -1;
  out[cb] = '\0';
  return 0;
}

static int bs_b64_dec(const char* text, unsigned char* out, size_t cap,
                      size_t* out_len) {
  DWORD cb = 0;
  if (!CryptStringToBinaryA(text, 0, CRYPT_STRING_BASE64, NULL, &cb, NULL,
                            NULL))
    return -1;
  if ((size_t)cb > cap) return -1;
  if (!CryptStringToBinaryA(text, 0, CRYPT_STRING_BASE64, out, &cb, NULL, NULL))
    return -1;
  if (out_len) *out_len = cb;
  return 0;
}

/* ---------------------------------------------------------------------------
 * MD5
 * ------------------------------------------------------------------------- */

static int bs_md5_hex(const char* in, char out[33]) {
  BCRYPT_ALG_HANDLE hAlg = NULL;
  BCRYPT_HASH_HANDLE hHash = NULL;
  unsigned char hash[16];
  int i;
  int rc = -1;

  out[0] = '\0';
  if (BCryptOpenAlgorithmProvider(&hAlg, BCRYPT_MD5_ALGORITHM, NULL, 0) != 0)
    goto done;
  if (BCryptCreateHash(hAlg, &hHash, NULL, 0, NULL, 0, 0) != 0) goto done;
  if (BCryptHashData(hHash, (PUCHAR)in, (ULONG)strlen(in), 0) != 0) goto done;
  if (BCryptFinishHash(hHash, hash, sizeof(hash), 0) != 0) goto done;
  for (i = 0; i < 16; i++) snprintf(out + i * 2, 3, "%02x", hash[i]);
  out[32] = '\0';
  rc = 0;

done:
  if (hHash) BCryptDestroyHash(hHash);
  if (hAlg) BCryptCloseAlgorithmProvider(hAlg, 0);
  return rc;
}

/* ---------------------------------------------------------------------------
 * AES-128-CBC：密钥 16 字节，IV = 密钥（BSPHP 的约定），PKCS7 填充
 * ------------------------------------------------------------------------- */

static int bs_aes_crypt(int enc, const char* key16, const unsigned char* in,
                        size_t in_len, unsigned char* out, size_t out_cap,
                        size_t* out_len) {
  BCRYPT_ALG_HANDLE hAlg = NULL;
  BCRYPT_KEY_HANDLE hKey = NULL;
  BCRYPT_KEY_DATA_BLOB_HEADER* hdr = NULL;
  size_t blob_len = sizeof(BCRYPT_KEY_DATA_BLOB_HEADER) + 16;
  unsigned char iv[16];
  ULONG cb = 0;
  int rc = -1;

  memcpy(iv, key16, 16);
  hdr = (BCRYPT_KEY_DATA_BLOB_HEADER*)malloc(blob_len);
  if (hdr == NULL) goto done;
  hdr->dwMagic = BCRYPT_KEY_DATA_BLOB_MAGIC;
  hdr->dwVersion = BCRYPT_KEY_DATA_BLOB_VERSION1;
  hdr->cbKeyData = 16;
  memcpy((unsigned char*)hdr + sizeof(BCRYPT_KEY_DATA_BLOB_HEADER), key16, 16);

  if (BCryptOpenAlgorithmProvider(&hAlg, BCRYPT_AES_ALGORITHM, NULL, 0) != 0)
    goto done;
  if (BCryptSetProperty(hAlg, BCRYPT_CHAINING_MODE,
                        (PUCHAR)BCRYPT_CHAIN_MODE_CBC,
                        sizeof(BCRYPT_CHAIN_MODE_CBC), 0) != 0)
    goto done;
  if (BCryptImportKey(hAlg, NULL, BCRYPT_KEY_DATA_BLOB, &hKey, NULL, 0,
                      (PUCHAR)hdr, (ULONG)blob_len, 0) != 0)
    goto done;

  if (enc) {
    if (BCryptEncrypt(hKey, (PUCHAR)in, (ULONG)in_len, NULL, iv, 16, out,
                      (ULONG)out_cap, &cb, BCRYPT_BLOCK_PADDING) != 0)
      goto done;
  } else {
    if (BCryptDecrypt(hKey, (PUCHAR)in, (ULONG)in_len, NULL, iv, 16, out,
                      (ULONG)out_cap, &cb, BCRYPT_BLOCK_PADDING) != 0)
      goto done;
  }
  *out_len = cb;
  rc = 0;

done:
  if (hdr) free(hdr);
  if (hKey) BCryptDestroyKey(hKey);
  if (hAlg) BCryptCloseAlgorithmProvider(hAlg, 0);
  return rc;
}

/* AES 加密 + Base64 输出。 */
static int bs_aes_enc_b64(const char* key16, const char* plain, char* out_b64,
                          size_t cap) {
  unsigned char* ct = NULL;
  size_t ct_cap = strlen(plain) + 32;
  size_t ct_len = 0;
  int rc = -1;

  out_b64[0] = '\0';
  ct = (unsigned char*)malloc(ct_cap);
  if (ct == NULL) goto done;
  if (bs_aes_crypt(1, key16, (const unsigned char*)plain, strlen(plain), ct,
                   ct_cap, &ct_len) != 0)
    goto done;
  if (bs_b64_enc(ct, ct_len, out_b64, cap) != 0) goto done;
  rc = 0;

done:
  if (ct) free(ct);
  return rc;
}

/* Base64 + AES 解密，输出 NUL 结尾文本。 */
static int bs_aes_dec_b64(const char* key16, const char* b64, char* out,
                          size_t cap) {
  unsigned char* ct = NULL;
  size_t ct_len = 0;
  size_t pt_len = 0;
  int rc = -1;

  out[0] = '\0';
  ct = (unsigned char*)malloc(strlen(b64) + 16);
  if (ct == NULL) goto done;
  if (bs_b64_dec(b64, ct, strlen(b64) + 16, &ct_len) != 0) goto done;
  if (ct_len == 0 || ct_len % 16 != 0) goto done;
  if (bs_aes_crypt(0, key16, ct, ct_len, (unsigned char*)out, cap, &pt_len) != 0)
    goto done;
  if (pt_len >= cap) goto done;
  out[pt_len] = '\0';
  rc = 0;

done:
  if (ct) free(ct);
  return rc;
}

/* ---------------------------------------------------------------------------
 * RSA：客户端公钥加密（X.509 SPKI Base64）、服务端私钥解密（PKCS#8 Base64）
 * ------------------------------------------------------------------------- */

static int bs_rsa_pub_enc(const char* spki_b64, const char* msg, char* out_b64,
                          size_t cap) {
  unsigned char der[1024];
  size_t der_len = 0;
  PCERT_PUBLIC_KEY_INFO pki = NULL;
  DWORD cbPKI = 0;
  BCRYPT_KEY_HANDLE hKey = NULL;
  unsigned char* ct = NULL;
  ULONG ct_len = 0;
  NTSTATUS st;
  int rc = -1;

  out_b64[0] = '\0';
  if (bs_b64_dec(spki_b64, der, sizeof(der), &der_len) != 0) goto done;
  if (!CryptDecodeObjectEx(X509_ASN_ENCODING, X509_PUBLIC_KEY_INFO, der,
                           (DWORD)der_len, CRYPT_DECODE_ALLOC_FLAG, NULL, &pki,
                           &cbPKI))
    goto done;
  if (!CryptImportPublicKeyInfoEx2(X509_ASN_ENCODING, pki, 0, NULL, &hKey))
    goto done;

  st = BCryptEncrypt(hKey, (PUCHAR)msg, (ULONG)strlen(msg), NULL, NULL, 0, NULL,
                     0, &ct_len, BCRYPT_PAD_PKCS1);
  if (st != 0) goto done;
  ct = (unsigned char*)malloc(ct_len);
  if (ct == NULL) goto done;
  st = BCryptEncrypt(hKey, (PUCHAR)msg, (ULONG)strlen(msg), NULL, NULL, 0, ct,
                     ct_len, &ct_len, BCRYPT_PAD_PKCS1);
  if (st != 0) goto done;
  if (bs_b64_enc(ct, ct_len, out_b64, cap) != 0) goto done;
  rc = 0;

done:
  if (ct) free(ct);
  if (hKey) BCryptDestroyKey(hKey);
  if (pki) LocalFree(pki);
  return rc;
}

/* --- PKCS#8 → BCRYPT_RSAPRIVATE_BLOB（与 pc_shide.c 同一套 ASN.1 走法）--- */

typedef struct {
  const unsigned char* p;
  size_t n;
} bs_int_t;

static int bs_asn1_len(const unsigned char** pp, const unsigned char* end,
                       size_t* out) {
  const unsigned char* p = *pp;
  size_t n;
  if (p >= end) return 0;
  n = *p++;
  if (n & 0x80) {
    size_t nb = n & 0x7f;
    size_t total = 0;
    while (nb-- > 0) {
      if (p >= end) return 0;
      total = (total << 8) | *p++;
    }
    n = total;
  }
  *pp = p;
  *out = n;
  return 1;
}

static int bs_asn1_int(const unsigned char** pp, const unsigned char* end,
                       bs_int_t* out) {
  const unsigned char* p = *pp;
  size_t n;
  if (p >= end || *p++ != 0x02) return 0;
  if (!bs_asn1_len(&p, end, &n)) return 0;
  if (p + n > end) return 0;
  out->p = p;
  out->n = n;
  *pp = p + n;
  return 1;
}

static void bs_strip_be(bs_int_t* v) {
  while (v->n > 1 && v->p[0] == 0) {
    v->p++;
    v->n--;
  }
}

/* 右对齐写入大端字段（高位补 0）。
 *
 * 【必须钳位】早先这里直接 `pad = dst_len - v->n`：DER 解析出来的 dp / dq /
 * qinv 长度没有任何校验，一旦 v->n > dst_len，size_t 就下溢成天文数字，
 * 紧跟的 memset 立刻写出分配区 —— 堆损坏，崩溃点离这里很远。
 * 对照 pc_shide.c 的 sh_put_be 里有 `if (val_len > dst_len) val_len = dst_len;`
 * 这一行钳位，本文件漏了；现在补齐，并且取**低 dst_len 字节**（大端右对齐的
 * 语义），与那边保持一致。 */
static void bs_put_be(unsigned char* dst, size_t dst_len, const bs_int_t* v) {
  size_t n;
  if (dst == NULL || v == NULL || v->p == NULL || dst_len == 0) return;
  n = v->n;
  if (n > dst_len) n = dst_len;
  memset(dst, 0, dst_len);
  memcpy(dst + (dst_len - n), v->p + (v->n - n), n);
}

static int bs_rsa_import_priv(const char* pkcs8_b64, BCRYPT_ALG_HANDLE* out_alg,
                              BCRYPT_KEY_HANDLE* out_key) {
  unsigned char der[4096];
  size_t der_len = 0;
  bs_int_t n = {NULL, 0}, e = {NULL, 0}, d = {NULL, 0};
  bs_int_t p1 = {NULL, 0}, q1 = {NULL, 0}, dp = {NULL, 0}, dq = {NULL, 0},
           qinv = {NULL, 0};
  BCRYPT_ALG_HANDLE hAlg = NULL;
  BCRYPT_KEY_HANDLE hKey = NULL;
  BCRYPT_RSAKEY_BLOB* blob = NULL;
  size_t blob_len;
  int rc = -1;

  if (bs_b64_dec(pkcs8_b64, der, sizeof(der), &der_len) != 0) goto done;
  {
    const unsigned char* q = der;
    const unsigned char* end = der + der_len;
    size_t len;
    bs_int_t ver;
    /* PrivateKeyInfo ::= SEQUENCE { version, algorithm, privateKey OCTET } */
    if (q >= end || *q++ != 0x30) goto done;
    if (!bs_asn1_len(&q, end, &len)) goto done;
    if (!bs_asn1_int(&q, end, &ver)) goto done;
    if (q >= end || *q++ != 0x30) goto done; /* algorithm */
    if (!bs_asn1_len(&q, end, &len)) goto done;
    q += len;
    if (q >= end || *q++ != 0x04) goto done; /* privateKey */
    if (!bs_asn1_len(&q, end, &len)) goto done;
    if (q + len > end) goto done;
    /* 内层 RSAPrivateKey */
    {
      const unsigned char* r = q;
      const unsigned char* rend = q + len;
      if (r >= rend || *r++ != 0x30) goto done;
      if (!bs_asn1_len(&r, rend, &len)) goto done;
      if (!bs_asn1_int(&r, rend, &ver)) goto done;
      if (!bs_asn1_int(&r, rend, &n)) goto done;
      if (!bs_asn1_int(&r, rend, &e)) goto done;
      if (!bs_asn1_int(&r, rend, &d)) goto done;
      if (!bs_asn1_int(&r, rend, &p1)) goto done;
      if (!bs_asn1_int(&r, rend, &q1)) goto done;
      if (!bs_asn1_int(&r, rend, &dp)) goto done;
      if (!bs_asn1_int(&r, rend, &dq)) goto done;
      if (!bs_asn1_int(&r, rend, &qinv)) goto done;
    }
  }

  bs_strip_be(&n);
  bs_strip_be(&e);
  bs_strip_be(&d);
  bs_strip_be(&p1);
  bs_strip_be(&q1);
  bs_strip_be(&dp);
  bs_strip_be(&dq);
  bs_strip_be(&qinv);
  if (n.n == 0 || n.n > 1024 || e.n == 0 || d.n == 0 || p1.n == 0 || q1.n == 0)
    goto done;

  {
    ULONG exp_pad = (ULONG)((e.n + 3) & ~3UL);
    ULONG cbN = (ULONG)n.n, cbP = (ULONG)p1.n, cbQ = (ULONG)q1.n;
    unsigned char* dst;
    blob_len = sizeof(BCRYPT_RSAKEY_BLOB) + exp_pad + cbN + cbP + cbQ + cbP +
               cbQ + cbP + cbN;
    blob = (BCRYPT_RSAKEY_BLOB*)malloc(blob_len);
    if (blob == NULL) goto done;
    blob->Magic = BCRYPT_RSAPRIVATE_MAGIC;
    blob->BitLength = (ULONG)(n.n * 8);
    blob->cbPublicExp = exp_pad;
    blob->cbModulus = cbN;
    blob->cbPrime1 = cbP;
    blob->cbPrime2 = cbQ;
    dst = (unsigned char*)(blob + 1);
    bs_put_be(dst, exp_pad, &e);    dst += exp_pad;
    bs_put_be(dst, cbN, &n);        dst += cbN;
    bs_put_be(dst, cbP, &p1);       dst += cbP;
    bs_put_be(dst, cbQ, &q1);       dst += cbQ;
    bs_put_be(dst, cbP, &dp);       dst += cbP;
    bs_put_be(dst, cbQ, &dq);       dst += cbQ;
    bs_put_be(dst, cbP, &qinv);     dst += cbP;
    bs_put_be(dst, cbN, &d);        dst += cbN;
  }

  if (BCryptOpenAlgorithmProvider(&hAlg, BCRYPT_RSA_ALGORITHM, NULL, 0) != 0)
    goto done;
  if (BCryptImportKeyPair(hAlg, NULL, BCRYPT_RSAPRIVATE_BLOB, &hKey,
                          (PUCHAR)blob, (ULONG)blob_len, 0) != 0)
    goto done;

  *out_alg = hAlg;
  *out_key = hKey;
  hAlg = NULL;
  hKey = NULL;
  rc = 0;

done:
  if (blob) free(blob);
  if (hKey) BCryptDestroyKey(hKey);
  if (hAlg) BCryptCloseAlgorithmProvider(hAlg, 0);
  return rc;
}

static int bs_rsa_priv_dec(const char* pkcs8_b64, const char* cipher_b64,
                           char* out, size_t cap) {
  BCRYPT_ALG_HANDLE hAlg = NULL;
  BCRYPT_KEY_HANDLE hKey = NULL;
  unsigned char ct[1024];
  size_t ct_len = 0;
  ULONG pt_len = 0;
  int rc = -1;

  out[0] = '\0';
  if (bs_rsa_import_priv(pkcs8_b64, &hAlg, &hKey) != 0) goto done;
  if (bs_b64_dec(cipher_b64, ct, sizeof(ct), &ct_len) != 0) goto done;
  if (ct_len == 0) goto done;
  if (BCryptDecrypt(hKey, ct, (ULONG)ct_len, NULL, NULL, 0, NULL, 0, &pt_len,
                    BCRYPT_PAD_PKCS1) != 0)
    goto done;
  if ((size_t)pt_len >= cap) goto done;
  if (BCryptDecrypt(hKey, ct, (ULONG)ct_len, NULL, NULL, 0, (PUCHAR)out, pt_len,
                    &pt_len, BCRYPT_PAD_PKCS1) != 0)
    goto done;
  out[pt_len] = '\0';
  rc = 0;

done:
  if (hKey) BCryptDestroyKey(hKey);
  if (hAlg) BCryptCloseAlgorithmProvider(hAlg, 0);
  return rc;
}

/* ---------------------------------------------------------------------------
 * URL 编解码：与 demo 一致 —— '+' 不当空格（响应里的 Base64 含 '+'）
 * ------------------------------------------------------------------------- */

static void bs_url_encode(const char* src, char* out, size_t cap) {
  size_t i, j = 0;
  out[0] = '\0';
  for (i = 0; src[i] != '\0' && j + 4 < cap; i++) {
    unsigned char c = (unsigned char)src[i];
    if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
        (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~') {
      out[j++] = (char)c;
    } else {
      snprintf(out + j, cap - j, "%%%02X", c);
      j += 3;
    }
  }
  out[j] = '\0';
}

static int bs_hex_nibble(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
  if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
  return -1;
}

static void bs_url_decode(const char* src, char* out, size_t cap) {
  size_t i = 0, j = 0;
  out[0] = '\0';
  while (src[i] != '\0' && j + 1 < cap) {
    if (src[i] == '%' && src[i + 1] != '\0' && src[i + 2] != '\0') {
      int hi = bs_hex_nibble(src[i + 1]);
      int lo = bs_hex_nibble(src[i + 2]);
      if (hi >= 0 && lo >= 0) {
        out[j++] = (char)((unsigned char)((hi << 4) | lo));
        i += 3;
        continue;
      }
    }
    out[j++] = src[i++];
  }
  out[j] = '\0';
}

/* ---------------------------------------------------------------------------
 * 时间格式：date 用 "%Y-%m-%d#%H:%M:%S"，appsafecode 用 "%Y-%m-%d %H:%M:%S"
 * ------------------------------------------------------------------------- */

static void bs_times(char t_normal[20], char t_hash[20]) {
  time_t t = time(NULL);
  struct tm tmv;
  localtime_s(&tmv, &t);
  strftime(t_normal, 20, "%Y-%m-%d %H:%M:%S", &tmv);
  strftime(t_hash, 20, "%Y-%m-%d#%H:%M:%S", &tmv);
}

/* ---------------------------------------------------------------------------
 * 核心：组包 → 加密 → POST → 解密
 * ------------------------------------------------------------------------- */

/* 心跳（timeout.lg）是后台静默调用：它每 10 分钟一次，成功也好、网络失败
   也好都不该往日志里刷 —— 唯一的例外是「会话失效 → 结束进程」那一条，
   由 hb_loop 自己写。这里据此让心跳跳过传输层的失败日志。 */
static int bs_api_silent(const char* api) {
  return api != NULL && strcmp(api, "timeout.lg") == 0;
}

/* 返回值改成状态码：网络层失败与「包组不出来 / 响应解不开」必须能分开。
 *
 * 之前一律返回 -1，上层只能映射成 PC_ERR_SERVER（服务端拒绝），于是断网时
 * 用户看到的是「验证请求失败」—— 而这类失败本来是可以重试的。现在：
 *   PC_ERR_NETWORK —— 连接 / 超时 / 非 200，调用方提示「检查网络后重试」；
 *   PC_ERR_SERVER  —— 组包或解密失败、响应不完整，一律当服务端问题。 */
static int32_t bs_send(const char* api, const char* extra, char* out_json,
                       size_t cap) {
  char t1[20], t2[20], appsafecode[33], md5_self[33], key_md5[33];
  char aes_key[17], sig_md5[33], sessl[256];
  char req_plain[4096], md5_seed[4096];
  /* aes_key = MD5(服务端私钥 + appsafecode) 的前 16 个 hex 字符。
   *
   * key_seed 必须装得下【完整私钥 + appsafecode】：服务端私钥 Base64 是 1624
   * 字节，加 32 字节 appsafecode 共 1656。参考实现（原 Dart 版 bsphp.dart:195）
   * 用的是完整私钥 —— `md5Hex('$serverPrivB64$appsafecode').substring(0, 16)`。
   *
   * 这里曾经是 `char signature[512]` 兼作两用（既拼 key 的种子、又装签名行），
   * snprintf 会把私钥静默截到 511 字节 —— 拼出来的种子实际只有私钥前 511 字节，
   * appsafecode 根本没进去，算出的 key 与参考实现不同。
   * 之所以一直没暴露，是因为 AES key 会由 signature 明文带给服务端、
   * 服务端用它解密（不自行推导比对），所以截断值也能跑通；
   * 但这是缓冲区太小的意外产物，不是协议约定，一旦服务端改成自行校验就会失败。
   * 现在拆成两个变量：key_seed 给足容量，signature 只装短签名行。 */
  char key_seed[2048];
  char signature[256];
  /* 大缓冲放堆上（合计约 38KB 栈）。
   *
   * 为什么：本函数经 pc_auth_* → Isolate.run 的 isolate 线程进来，那条线程
   * 只有约 1MB 栈（不是引擎工作线程的 4MB），叠上 FFI 与调试版 VM 的栈帧后
   * 余量并不宽裕；再加一层调用就可能 EXCEPTION_STACK_OVERFLOW —— 栈溢出会
   * 让进程直接消失，连崩溃处理器都未必能跑起来。这几个缓冲没有任何必须
   * 放在栈上的理由，挪到堆上一次性把风险消掉。 */
  char* enc_b64 = NULL;
  char* rsa_b64 = NULL;
  char* payload = NULL;
  char* resp = NULL;
  bs_cfg_snapshot_t cfg;
  char* encoded = NULL;
  char* form = NULL;
  char* decoded = NULL;
  pc_http_result res;
  int32_t rc = PC_ERR_SERVER;

  enc_b64 = (char*)malloc(8192);
  rsa_b64 = (char*)malloc(1024);
  payload = (char*)malloc(16384);
  resp = (char*)malloc(8192);
  if (enc_b64 == NULL || rsa_b64 == NULL || payload == NULL || resp == NULL) {
    pc_log("[BSPHP] %s 失败：内存不足", api);
    free(enc_b64); free(rsa_b64); free(payload); free(resp);
    return PC_ERR_SERVER;
  }

  out_json[0] = '\0';

  /* 配置取一份一致快照：configure 可能正在别的线程改写这几个字段，
     直接读全局会拿到半写字符串（见 g_cfg_lock 的说明）。 */
  bs_cfg_snapshot(&cfg);

  if (cfg.priv_b64[0] == '\0' || cfg.pub_b64[0] == '\0') {
    /* 没有密钥就没法组包：提示到日志，交给上层当服务错误。心跳静默，不记。 */
    if (!bs_api_silent(api)) {
      pc_log("[BSPHP] %s 失败：未配置 RSA 密钥（服务端私钥 / 客户端公钥）", api);
      pc_log_flush();
    }
    /* 早退必须走统一释放路径：上面刚申请的 4 块堆缓冲（enc_b64 / rsa_b64 /
     * payload / resp，合计约 34KB）否则每次调用都会泄漏一次。 */
    goto done;
  }

  /* 会话串可能正被别的线程改写，先取一份本地快照再用，避免撕裂读。 */
  bs_sessl_snapshot(sessl, sizeof(sessl));

  bs_times(t1, t2);
  if (bs_md5_hex(t1, appsafecode) != 0) goto done;

  snprintf(md5_seed, sizeof(md5_seed),
           "api=%s&BSphpSeSsL=%s&date=%s&mutualkey=%s&appsafecode=%s%s%s", api,
           sessl, t2, cfg.mutual_key, appsafecode,
           (extra != NULL && extra[0] != '\0') ? "&" : "",
           (extra != NULL && extra[0] != '\0') ? extra : "");
  if (bs_md5_hex(md5_seed, md5_self) != 0) goto done;

  snprintf(req_plain, sizeof(req_plain),
           "api=%s&BSphpSeSsL=%s&date=%s&md5=%s&mutualkey=%s&appsafecode=%s%s%s",
           api, sessl, t2, md5_self, cfg.mutual_key, appsafecode,
           (extra != NULL && extra[0] != '\0') ? "&" : "",
           (extra != NULL && extra[0] != '\0') ? extra : "");

  snprintf(key_seed, sizeof(key_seed), "%s%s", cfg.priv_b64, appsafecode);
  if (bs_md5_hex(key_seed, key_md5) != 0) goto done;
  memcpy(aes_key, key_md5, 16);
  aes_key[16] = '\0';

  if (bs_aes_enc_b64(aes_key, req_plain, enc_b64, 8192) != 0)
    goto done;

  if (bs_md5_hex(enc_b64, sig_md5) != 0) goto done;
  snprintf(signature, sizeof(signature), "0|AES-128-CBC|%s|%s|%s", aes_key,
           sig_md5, BS_SIGN_TAIL);
  if (bs_rsa_pub_enc(cfg.pub_b64, signature, rsa_b64, 1024) != 0)
    goto done;

  snprintf(payload, 16384, "%s|%s", enc_b64, rsa_b64);
  encoded = (char*)malloc(strlen(payload) * 3 + 2);
  if (encoded == NULL) goto done;
  bs_url_encode(payload, encoded, strlen(payload) * 3 + 2);

  form = (char*)malloc(strlen(encoded) + 16);
  if (form == NULL) goto done;
  snprintf(form, strlen(encoded) + 16, "parameter=%s", encoded);

  res.http_status = 0;
  res.message[0] = '\0';
  resp[0] = '\0';
  if (pc_http_post(cfg.url, form, BS_CONNECT_MS, BS_READ_MS, resp, 8192, NULL,
                   &res) != PC_HTTP_OK) {
    if (!bs_api_silent(api)) {
      pc_log("[BSPHP] %s 网络失败：%s", api,
             res.message[0] != '\0' ? res.message : "无详情");
      pc_log_flush();
    }
    rc = PC_ERR_NETWORK;
    goto done;
  }

  decoded = (char*)malloc(strlen(resp) + 2);
  if (decoded == NULL) goto done;
  bs_url_decode(resp, decoded, strlen(resp) + 2);

  {
    /* 响应：first|AES|RSA —— 先用私钥解出响应 AES key，再解正文。 */
    char* work = _strdup(decoded);
    char* p1;
    char* p2;
    char sig_plain[1024];
    if (work == NULL) goto done;
    p1 = strchr(work, '|');
    p2 = (p1 != NULL) ? strchr(p1 + 1, '|') : NULL;
    if (p2 == NULL) {
      free(work);
      goto done;
    }
    *p1 = '\0';
    *p2 = '\0';
    if (bs_rsa_priv_dec(cfg.priv_b64, p2 + 1, sig_plain,
                        sizeof(sig_plain)) != 0) {
      free(work);
      goto done;
    }
    {
      /* sig_plain: 0|AES-128-CBC|<16位key>|MD5|json */
      char* k1 = strchr(sig_plain, '|');
      char* k2 = (k1 != NULL) ? strchr(k1 + 1, '|') : NULL;
      char* k3 = (k2 != NULL) ? strchr(k2 + 1, '|') : NULL;
      char resp_key[17];
      if (k3 == NULL || (size_t)(k3 - (k2 + 1)) < 16) {
        free(work);
        goto done;
      }
      memcpy(resp_key, k2 + 1, 16);
      resp_key[16] = '\0';
      if (bs_aes_dec_b64(resp_key, p1 + 1, out_json, cap) != 0) {
        free(work);
        goto done;
      }
    }
    free(work);
  }
  rc = PC_OK;

done:
  if (encoded) free(encoded);
  if (form) free(form);
  if (decoded) free(decoded);
  free(enc_b64);
  free(rsa_b64);
  free(payload);
  free(resp);
  return rc;
}

/* ---------------------------------------------------------------------------
 * 导出接口
 * ------------------------------------------------------------------------- */

void pc_bsphp_configure(const char* api_url, const char* mutual_key,
                        const char* server_priv_b64,
                        const char* client_pub_b64) {
  /* 独占写：bs_send 会取共享快照，避免运行期 configure 时读到半写字符串。 */
  AcquireSRWLockExclusive(&g_cfg_lock);
  if (api_url != NULL) bs_copy(g_bs.url, sizeof(g_bs.url), api_url);
  if (mutual_key != NULL)
    bs_copy(g_bs.mutual_key, sizeof(g_bs.mutual_key), mutual_key);
  if (server_priv_b64 != NULL)
    bs_copy(g_bs.priv_b64, sizeof(g_bs.priv_b64), server_priv_b64);
  if (client_pub_b64 != NULL)
    bs_copy(g_bs.pub_b64, sizeof(g_bs.pub_b64), client_pub_b64);
  ReleaseSRWLockExclusive(&g_cfg_lock);
}

int32_t pc_bsphp_bootstrap(void) {
  char json[8192];
  char sessl[256];
  int32_t rc;

  /* 【不再先清空旧会话】
   *
   * 原实现在这里 bs_sessl_store("") —— 本意是「握手万一中途失败，绝不能继续拿
   * 上一次的会话串发请求」。但它带来两个更严重的问题：
   *
   *   1) 空窗期：清空之后还要发两个真实网络请求（internet.in +
   *      BSphpSeSsL.in，最长 10s + 15s）。这段时间全局会话串是空串，后台心跳
   *      线程若在此刻醒来打 timeout.lg，服务端 Plug_User_Is_Login_Seesion()
   *      直接回 1049，而 1049 在心跳门禁里是「会话已死」→ ExitProcess。
   *      表现为「偶发秒退」。
   *   2) 并发覆盖：公告 gg.in 与心跳是并发起的（main.dart 的 pcAuthNoticeAsync
   *      与 work_page 的 pcHeartbeatStart），公告走 ensure() → bootstrap，
   *      会把刚登录成功的会话串清掉。
   *
   * 改成「拿到新会话才一次性提交」：握手失败时旧会话仍可用（下次调用会重新
   * 握手）；而「让旧会话彻底失效」交给 pc_auth_bsphp_reset() 显式调
   * pc_bsphp_clear_session() 去做，不在握手途中制造空窗。 */

  rc = bs_send("internet.in", "", json, sizeof(json));
  if (rc != PC_OK) return rc;

  rc = bs_send("BSphpSeSsL.in", "", json, sizeof(json));
  if (rc != PC_OK) return rc;

  /* 这里**不能**拿业务码表判 code：握手接口的 code 与业务码表不是一套语义。
     实测 BSphpSeSsL.in 正常握手时回 code=1000，而业务表里 1000 是
     「用户已经存在」的失败码 —— 硬判会把正常握手也毙掉（曾因此误报
     「网络验证握手失败」）。DEMO 的 bsphp_bootstrap 同样不做码判定，只取 data。 */

  /* 拿不到会话串 = 握手没真正成功。以前这里取不到也照样返回 PC_OK，
     结果后续请求带着空会话串去撞运气，报错位置离真正的原因很远。 */
  if (!pc_bsphp_json_field(json, "data", sessl, sizeof(sessl)) ||
      sessl[0] == '\0') {
    pc_log("[BSPHP] 握手失败：响应里没有可用的会话串");
    pc_log_flush();
    return PC_ERR_SERVER;
  }

  /* 【关键】握手串是匿名会话（BSphpSeSsL.in 走 Plug_Session_Appen_Open
     ('NEWSESSION') 新建 session），**不带登录态**。手上已经有登录会话时绝不能
     拿它覆盖 —— 否则下一次 timeout.lg 必然被服务端判为「未登录(1049)」。

     【这里是 check-then-act，必须原子】
     早先写成「先读 g_sessl_has_login 判断、else 分支里再 store」两步，中间
     没有锁保护。窗口内若 login.lg 成功并写入登录会话，这次 store 就会把匿名
     握手串盖到登录会话上 —— 心跳随即 1049，配合旧 FATAL 表直接杀进程。
     现在合成一次「仅当无登录会话时才写」的原子操作。 */
  if (!bs_sessl_store_anon_if_no_login(sessl)) {
    pc_log("[BSPHP] 已有登录会话，握手匿名串不覆盖当前会话");
    pc_log_flush();
  }
  return PC_OK;
}

int32_t pc_bsphp_call(const char* api, const char* extra, char* out_json,
                      size_t cap) {
  if (api == NULL || out_json == NULL || cap == 0) return PC_ERR_INVALID_ARG;
  /* 原样透传：PC_ERR_NETWORK（可重试）与 PC_ERR_SERVER（服务端拒绝）必须
     保持区分，否则上层只能一律提示「验证失败」，断网重试的文案就丢了。 */
  return bs_send(api, extra, out_json, cap);
}

int32_t pc_bsphp_login(const char* user, const char* pwd, const char* machine,
                       char* out_json, size_t cap) {
  char extra[1024];
  extra[0] = '\0';
  /* 一律经 bs_append_param 拼装：密码 / 卡密没有字符集限制，值里的 '&' '=' 会
     把参数拆错，服务端解出来就是个错的密码，用户只会看到「密码错误」。 */
  if (bs_append_param(extra, sizeof(extra), "user", user != NULL ? user : "") != 0 ||
      bs_append_param(extra, sizeof(extra), "pwd", pwd != NULL ? pwd : "") != 0 ||
      bs_append_param(extra, sizeof(extra), "coode", "") != 0 ||
      bs_append_param(extra, sizeof(extra), "key", machine != NULL ? machine : "") != 0 ||
      bs_append_param(extra, sizeof(extra), "maxoror", machine != NULL ? machine : "") != 0) {
    /* 参数超长（密码/卡密里有大量需要 %XX 编码的字符时可能撑爆 1KB）。
       早先返回 PC_ERR_SERVER，界面提示「服务器错误」，排查方向完全跑偏；
       这是本地入参问题，必须报参数错误。 */
    pc_log("登录参数超长，请缩短密码或换用纯英文数字字符");
    return PC_ERR_INVALID_ARG;
  }
  return pc_bsphp_call("login.lg", extra, out_json, cap);
}

int32_t pc_bsphp_register_by_card(const char* user, const char* pwd,
                                  const char* card, const char* machine,
                                  char* out_json, size_t cap) {
  char extra[1024];
  extra[0] = '\0';
  if (bs_append_param(extra, sizeof(extra), "user", user != NULL ? user : "") != 0 ||
      bs_append_param(extra, sizeof(extra), "pwd", pwd != NULL ? pwd : "") != 0 ||
      bs_append_param(extra, sizeof(extra), "pwdb", pwd != NULL ? pwd : "") != 0 ||
      bs_append_param(extra, sizeof(extra), "kaid", card != NULL ? card : "") != 0 ||
      bs_append_param(extra, sizeof(extra), "kapwd", "") != 0 ||
      bs_append_param(extra, sizeof(extra), "key", machine != NULL ? machine : "") != 0 ||
      bs_append_param(extra, sizeof(extra), "coode", "") != 0) {
    pc_log("注册参数超长，请缩短卡密或密码");
    return PC_ERR_INVALID_ARG;
  }
  return pc_bsphp_call("registrationaska.lg", extra, out_json, cap);
}

int32_t pc_bsphp_pay(const char* user, const char* user_pwd, const char* card,
                     char* out_json, size_t cap) {
  char extra[1024];
  extra[0] = '\0';
  if (bs_append_param(extra, sizeof(extra), "user", user != NULL ? user : "") != 0 ||
      bs_append_param(extra, sizeof(extra), "userpwd", user_pwd != NULL ? user_pwd : "") != 0 ||
      bs_append_param(extra, sizeof(extra), "userset", "1") != 0 ||
      bs_append_param(extra, sizeof(extra), "ka", card != NULL ? card : "") != 0 ||
      bs_append_param(extra, sizeof(extra), "pwd", "") != 0) {
    pc_log("充值参数超长，请缩短卡号");
    return PC_ERR_INVALID_ARG;
  }
  return pc_bsphp_call("chong.lg", extra, out_json, cap);
}

int32_t pc_bsphp_notice(char* out_json, size_t cap) {
  return pc_bsphp_call("gg.in", "", out_json, cap);
}

int pc_bsphp_json_field(const char* json, const char* key, char* out,
                        size_t cap) {
  const char* b = NULL;
  const char* e = NULL;
  size_t n;

  if (out == NULL || cap == 0) return 0;
  out[0] = '\0';
  if (json == NULL || key == NULL) return 0;

  /* 复用 bs_json_value：只认对象成员名（避开字符串值里的同名片段）、容忍
     "key" : 值 的空白、字符串按 \" 成对跳过不会提前截断。 */
  if (!bs_json_value(json, key, &b, &e)) return 0;
  n = (size_t)(e - b);
  if (n >= cap) n = cap - 1;
  memcpy(out, b, n);
  out[n] = '\0';
  return 1;
}

/* ---------------------------------------------------------------------------
 * 登录心跳（timeout.lg）与循环线程
 * ------------------------------------------------------------------------- */

/* 心跳间隔：固定 10 分钟一次。 */
#define HB_INTERVAL_MS (10 * 60 * 1000)

/* 心跳线程句柄 / 唤醒事件 / 停止请求 / 运行标志。
 *
 * 取消「用同一个 manual-reset 事件既当停止信号又当睡醒信号」的旧写法 —— 那个
 * 写法在「快速离开工作台又立刻回来」时会静默停死：stop 置了事件，但旧线程还堵
 * 在网络调用里没退，running 仍为 1；此时 start 看到线程句柄非空就当作「已在跑」
 * 直接返回，既没复位事件也没起新线程，等旧线程退掉后心跳就再也没人管了。
 *
 * 现方案：
 *   - g_hb_stop_req 是与线程分开的**停止请求**（g_hb_lock 保护），不再兼职唤醒；
 *   - g_hb_wake 是 **auto-reset** 事件，只负责「把睡着的线程拍醒」；
 *   - 线程每轮心跳后等待 g_hb_wake，醒来**在锁内**读 g_hb_stop_req 决定是否退出，
 *     并把 running 归零 —— 与 start/stop 的判断在同一把锁下，杜绝上面那个竞态。
 * 静态初始化 SRWLOCK，避免惰性初始化本身的竞态（与 g_sessl_lock 同思路）。 */
static SRWLOCK g_hb_lock = SRWLOCK_INIT;
static HANDLE g_hb_thread = NULL;
static HANDLE g_hb_wake = NULL;      /* auto-reset 唤醒事件 */
static volatile LONG g_hb_running = 0;
static int g_hb_stop_req = 0;        /* g_hb_lock 保护：1=请求线程退出 */

/* 单次心跳：timeout.lg，无额外参数，用当前会话串。 */
int32_t pc_bsphp_heartbeat(char* out_json, size_t cap) {
  return pc_bsphp_call("timeout.lg", "", out_json, cap);
}

/* 该接口的响应 SeSsL 是否允许写入全局会话。
 *
 * 服务端**每个响应**都回显 session_id()（见 applibapi/output/bsphp_json.php 的
 * $json_array['response']['SeSsL'] = session_id()），所以「响应里有 SeSsL」
 * 完全不等于「这条会话带登录态」。下面这些接口回的是匿名会话：
 *
 *   internet.in / BSphpSeSsL.in  —— 握手，服务端新建匿名 session
 *   gg.in                        —— 公告，不需要登录，服务端回匿名串
 *   registrationaska.lg          —— 卡注册，注册完还没登录，回匿名串
 *
 * 它们一旦写进 g_bs.sessl，就会把登录会话顶掉，下一次 timeout.lg 回 1049。
 * 只有真正建立登录态的接口才允许写。 */
static int bs_api_may_adopt_session(const char* api) {
  if (api == NULL) return 0;
  if (strcmp(api, "login.lg") == 0) return 1;
  /* chong.lg（充值 / VIP 续期）**不再**允许写会话。
   *
   * 早先把它也放进白名单，理由是「充值成功后服务端会建立登录态」。实际上
   * chong.lg 走的是「校验账号密码 + 核销卡密」分支，回显的 session_id() 仍是
   * 当前会话 —— 用户「先登录再充值」时它会把登录会话替换成一条未必带登录态的
   * 串，心跳随即 1049，配合重握手失败会进入「每 10 分钟失败一次、永不恢复」
   * 的状态。宁可不采用：登录会话由 login.lg 独家建立。 */
  return 0;
}

/* 采用业务响应里的新会话串（SeSsL），**按接口白名单**。
 *
 * api 为发起本次调用的接口名（如 "login.lg"）。白名单外的接口一律不写：
 * 宁可少写一次，也不能让匿名会话顶掉登录会话 —— 后者会让心跳 1049 自杀。 */
int pc_bsphp_adopt_session_ex(const char* api, const char* json) {
  char sessl[256];

  if (json == NULL) return 0;
  if (!bs_api_may_adopt_session(api)) return 0;
  if (pc_bsphp_json_field(json, "SeSsL", sessl, sizeof(sessl)) &&
      sessl[0] != '\0') {
    bs_sessl_store_ex(sessl, 1);   /* 1 = 带登录态 */
    return 1;
  }
  return 0;
}

/* 兼容旧调用点：不带接口名时按「不允许写入」处理（fail-closed）。
   旧的单参版本无差别采用响应 SeSsL，正是登录会话被匿名串覆盖的来源。 */
int pc_bsphp_adopt_session(const char* json) {
  (void)json;
  return 0;
}

/* 显式作废当前会话（会话自愈 / 退出登录时用）。
 *
 * 与 bootstrap 的分工：bootstrap 不再清空会话（避免空窗期），所以「让旧会话
 * 彻底失效」必须由调用方在需要时显式调用这里。 */
void pc_bsphp_clear_session(void) {
  bs_sessl_store_ex("", 0);
}

/* 串行化握手：所有 bootstrap 都必须经这里，共用 pc_auth.c 的握手锁。
 *
 * 为什么需要：bootstrap 本身要发两条真实请求（internet.in + BSphpSeSsL.in），
 * 最长 connect 10s + read 15s 各一次。若「登录 / 注册 / 充值 / 公告」与
 * 「心跳自愈」同时握手，会出现：
 *   · 两轮握手各建一条匿名会话，后完成的那条覆盖前一条，先完成的一方
 *     以为自己的会话有效，随后的业务请求带着一条已被顶掉的串；
 *   · pc_auth_bsphp_reset() 清掉会话之后，心跳这一轮的写入又把它盖回去，
 *     「会话自愈」永久失效。
 * 锁由 pigeon_core.c 提供（pc_boot_lock_acquire / release），保证只存在
 * 一把锁，不会出现两处各建一把的情况。 */
int32_t pc_bsphp_bootstrap_serialized(void) {
  int32_t rc;
  pc_boot_lock_acquire();
  rc = pc_bsphp_bootstrap();
  pc_boot_lock_release();
  return rc;
}

/* 循环线程：先打一次，再每 10 分钟一次；收到停止事件立即退出。
 *
 * 心跳是后台静默保活，**正常情况一概不打日志**（每 10 分钟刷一条只是噪声）。
 * 只有两类情况写日志：
 *   1) 命中 FATAL、即将结束进程 —— 这是事后排查「软件为什么自己关了」的唯一线索；
 *   2) TRANSIENT 且重试后仍失败 —— 让用户/开发者知道保活暂时不通，但程序继续跑。
 *
 * 三级处理（见 pc_bsphp_hb_classify）：
 *   PC_HB_FATAL     → 写日志 + 收尾 + ExitProcess；
 *   PC_HB_TRANSIENT → 重握手后重试一次；仍失败只记日志，继续下一周期；
 *   PC_HB_OK        → 静默。 */
static DWORD WINAPI hb_loop(LPVOID arg) {
  (void)arg;
  for (;;) {
    char json[8192];
    int32_t rc;
    int level;

    json[0] = '\0';
    rc = pc_bsphp_heartbeat(json, sizeof(json));
    level = pc_bsphp_hb_classify(rc, json);

    /* TRANSIENT：先自愈再判。绝大多数「1049 未登录」都能靠重新握手恢复 ——
       这是它不该杀进程的直接理由。重试一次仍不行就放弃本轮，下个周期再来。 */
    if (level == PC_HB_TRANSIENT) {
      int code = 0;
      (void)pc_bsphp_json_int(json, "code", &code);

      /* 只在「服务端明确给了失败码」时才重握手：
         纯网络失败重握手没有意义（反而多打两个必然失败的请求）。 */
      if (rc == PC_OK && code != 0) {
        /* 必须与 pc_auth.c 的 ensure() 共用同一把握手锁：早先这里直接调
           bootstrap，会与登录 / 注册 / 充值线程的握手并发，两轮握手各建一条
           匿名会话、互相覆盖，而 pc_auth_bsphp_reset() 的「清零 + 作废会话」
           也可能被这一轮的写入反向覆盖 —— 自愈就此失效。 */
        int32_t boot_rc = pc_bsphp_bootstrap_serialized();
        if (boot_rc == PC_OK) {
          json[0] = '\0';
          rc = pc_bsphp_heartbeat(json, sizeof(json));
          level = pc_bsphp_hb_classify(rc, json);
        }
      }

      /* 重试后升级成 FATAL（例如服务端在重握手期间回了 1046 被顶号），
         就按 FATAL 处理；否则只记一条日志，继续下一周期。 */
      if (level != PC_HB_FATAL) {
        pc_log_file(
            "[心跳] timeout.lg 暂时失败（%s），不终止，下个周期重试。"
            "rc=%d code=%d 原文=%s",
            pc_bsphp_hb_class_text(level), rc, code,
            json[0] != '\0' ? json : "(无响应)");
        WaitForSingleObject(g_hb_wake, HB_INTERVAL_MS);
        AcquireSRWLockExclusive(&g_hb_lock);
        if (g_hb_stop_req) {
          /* 【不能在这里清 running】
           * 清完之后还要 break → 函数返回 → 线程才真正退出，这段窗口里
           * stop / start 会看到 running==0 且句柄已被关掉，于是再起一条心跳
           * 线程 —— 两条线程并存，双倍消耗服务端在线名额（5048/5049/5050
           * 「在线数超限」FATAL 因此提前引爆）。running 统一在函数末尾清。 */
          ReleaseSRWLockExclusive(&g_hb_lock);
          break;
        }
        ReleaseSRWLockExclusive(&g_hb_lock);
        continue;
      }
    }

    if (level == PC_HB_FATAL) {
      int code = 0;
      const char* text;

      (void)pc_bsphp_json_int(json, "code", &code);
      text = pc_bsphp_code_text(code);
      /* 落盘而不是写控制台：进程结束后只有文件能留下来供事后排查。
         code + 官方文案 + 接口原文，足够还原服务端到底回了什么。 */
      pc_log_file(
          "[心跳] timeout.lg 判定为授权失效（%s），结束进程。"
          "code=%d msg=%s 原文=%s",
          pc_bsphp_hb_class_text(level), code,
          (text != NULL && text[0] != '\0') ? text : "(未收录)", json);
      /* 【不能再直接 ExitProcess】
       *
       * 早先这里是「写日志 → pc_log_shutdown() → ExitProcess(0)」：
       *   1) 从后台线程硬杀进程，pc_task_stop 的协作式收尾完全跳过 ——
       *      抢单引擎线程可能正持着 g_queue_lock / g_stat_lock / CRT 流锁，
       *      正在写的「账户信息.txt」「订单信息.txt」「记住密码」全部截断；
       *   2) ExitProcess 要等所有线程走完 DllMain(PROCESS_DETACH)，而引擎线程
       *      可能卡在最长 25s 的网络调用里 —— 用户看到的是「被杀之后僵住」；
       *   3) pc_log_shutdown() 与 UI 线程的 pc_core_shutdown 并发，触发
       *      非幂等的句柄双重关闭。
       *
       * 现在改成走与用户点关闭完全相同的收尾路径 pc_core_shutdown()
       * （停心跳 → 停引擎 → 掐网络 → 停日志 → TerminateProcess）。
       * pc_core_shutdown 内部用 Interlocked 保证只执行一次，多条线程同时
       * 触发也安全。 */
      pc_core_shutdown((int64_t)time(NULL) * 1000);
      return 0; /* 不可达 */
    }

    /* 睡到下一个周期；期间被唤醒（stop 或正常超时）后**在锁内**判断去留。
       在锁内读 stop_req 并同时把 running 归零，保证与 start/stop 的判断互斥：
       start 要么看到「还在跑」而复用，要么看到「已停」而重建，不会两头都漏。 */
    WaitForSingleObject(g_hb_wake, HB_INTERVAL_MS);
    AcquireSRWLockExclusive(&g_hb_lock);
    if (g_hb_stop_req) {
      /* 同上：running 留到函数末尾统一清，避免「已清零但线程还没退」的窗口。 */
      ReleaseSRWLockExclusive(&g_hb_lock);
      break;
    }
    ReleaseSRWLockExclusive(&g_hb_lock);
  }
  /* 【线程退出的最后一步才把 running 清零】
   *
   * 清 running 与「线程真正 return」之间只要还有一条语句，start 就可能在这段
   * 窗口里看到「running==0 + 句柄已关」而重建线程，与尚未返回的旧线程并存。
   * 放在 return 之前、并且持锁清，让 start 的「检查 → 复用 / 新建」与这里
   * 串行化：start 要么看到 running==1（复用），要么看到 running==0 且线程
   * 已经走到这一步（即将返回，start 会用 WaitForSingleObject 二次确认）。 */
  AcquireSRWLockExclusive(&g_hb_lock);
  g_hb_stop_req = 0;
  InterlockedExchange(&g_hb_running, 0);
  ReleaseSRWLockExclusive(&g_hb_lock);
  return 0;
}

int32_t pc_bsphp_heartbeat_start(void) {
  int32_t rc = PC_OK;

  AcquireSRWLockExclusive(&g_hb_lock);

  if (InterlockedCompareExchange(&g_hb_running, 0, 0) != 0) {
    /* 线程还活着：**复用**它，不叠加线程。同时清掉可能残留的停止请求与唤醒
       信号 —— 这正是旧写法会静默停死的场景（stop 后旧线程仍堵在网络调用里，
       running 还是 1；若此处直接 return，等它退掉就再没人管心跳了）。 */
    g_hb_stop_req = 0;
    if (g_hb_wake != NULL) ResetEvent(g_hb_wake);
    ReleaseSRWLockExclusive(&g_hb_lock);
    return PC_OK;
  }

  /* running == 0：线程已走到退出路径或从未启动。
   *
   * 【仍要二次确认线程真的返回】running 现在由 hb_loop 在**最后一步**（持锁）
   * 清零，清零到 return 之间只剩一条指令；但为了不依赖这种「只差一条指令」
   * 的时序假设，这里再用 0 超时的 WaitForSingleObject 问一次：
   *   · 已退出（WAIT_OBJECT_0）→ 关句柄，正常新建；
   *   · 还没完全返回（WAIT_TIMEOUT）→ 本次**不新建**，直接返回 PC_OK。
   *     下一次 start（界面重新进工作台 / 重试）会再走一遍，届时它一定已经退了。
   * 这样任何时序下都不可能同时存在两条心跳线程。 */
  if (g_hb_thread != NULL) {
    if (WaitForSingleObject(g_hb_thread, 0) != WAIT_OBJECT_0) {
      /* 旧线程还在收尾：复用它的「停止请求已复位」语义，本次不叠线程。 */
      g_hb_stop_req = 0;
      if (g_hb_wake != NULL) ResetEvent(g_hb_wake);
      ReleaseSRWLockExclusive(&g_hb_lock);
      return PC_OK;
    }
    CloseHandle(g_hb_thread);
    g_hb_thread = NULL;
  }
  if (g_hb_wake == NULL) {
    /* auto-reset（第二参 FALSE）：SetEvent 只放行一个等待者，且放行后自动复位，
       不会像旧的手动复位事件那样把「上一轮的停止信号」留给下一轮误消费。 */
    g_hb_wake = CreateEventW(NULL, FALSE, FALSE, NULL);
    if (g_hb_wake == NULL) {
      ReleaseSRWLockExclusive(&g_hb_lock);
      return PC_ERR_SERVER;
    }
  }
  g_hb_stop_req = 0;
  ResetEvent(g_hb_wake);
  InterlockedExchange(&g_hb_running, 1);
  g_hb_thread = CreateThread(NULL, 0, hb_loop, NULL, 0, NULL);
  if (g_hb_thread == NULL) {
    InterlockedExchange(&g_hb_running, 0);
    rc = PC_ERR_SERVER;
  }
  ReleaseSRWLockExclusive(&g_hb_lock);
  return rc;
}

int32_t pc_bsphp_heartbeat_stop(void) {
  AcquireSRWLockExclusive(&g_hb_lock);
  /* 置停止请求并拍醒睡着的线程；线程自己在锁内读 stop_req 后退出。 */
  g_hb_stop_req = 1;
  if (g_hb_wake != NULL) {
    SetEvent(g_hb_wake);
  }
  if (InterlockedCompareExchange(&g_hb_running, 0, 0) == 0) {
    /* 线程已经不在了：没有等待者会消费唤醒信号，顺手把标志与句柄清干净。
     *
     * 【只在确认已退出时关句柄】与 start 同一个判据：running==0 只说明线程
     * 走完了循环，未必已经 return。用 0 超时 Wait 问一次，确认退出了才关；
     * 没退出就留给下一次 start / stop 收割（句柄泄漏一个，换时序绝对干净）。 */
    g_hb_stop_req = 0;
    if (g_hb_wake != NULL) ResetEvent(g_hb_wake);
    if (g_hb_thread != NULL) {
      if (WaitForSingleObject(g_hb_thread, 0) == WAIT_OBJECT_0) {
        CloseHandle(g_hb_thread);
        g_hb_thread = NULL;
      }
    }
  }
  ReleaseSRWLockExclusive(&g_hb_lock);
  /* 协作式：立即返回，线程在网络调用返回后自行退出（最长约 25s）；
     句柄由下一次 start / stop 收割。 */
  return PC_OK;
}

int32_t pc_bsphp_heartbeat_is_running(void) {
  /* 与写侧统一走 Interlocked*：写侧混用了「锁内普通读」与 InterlockedExchange，
   * 读侧若还是裸读，在 C11 / TSan 语义下仍是数据竞态。这个接口会被 UI 每秒
   * 轮询一次（pigeon_core.dart 的 pcHeartbeatIsRunning），不能含糊。 */
  return InterlockedCompareExchange(&g_hb_running, 0, 0) != 0 ? 1 : 0;
}

#else /* !_WIN32 */

/* 非 Windows：编译得过、符号在，但联网/加解密路径不可用。 */

void pc_bsphp_configure(const char* api_url, const char* mutual_key,
                        const char* server_priv_b64,
                        const char* client_pub_b64) {
  (void)api_url;
  (void)mutual_key;
  (void)server_priv_b64;
  (void)client_pub_b64;
}

int32_t pc_bsphp_bootstrap(void) { return PC_ERR_NETWORK; }

int32_t pc_bsphp_call(const char* api, const char* extra, char* out_json,
                      size_t cap) {
  (void)api;
  (void)extra;
  if (out_json != NULL && cap > 0) out_json[0] = '\0';
  return PC_ERR_NETWORK;
}

int32_t pc_bsphp_login(const char* user, const char* pwd, const char* machine,
                       char* out_json, size_t cap) {
  return pc_bsphp_call("login.lg", "", out_json, cap);
}

int32_t pc_bsphp_register_by_card(const char* user, const char* pwd,
                                  const char* card, const char* machine,
                                  char* out_json, size_t cap) {
  return pc_bsphp_call("registrationaska.lg", "", out_json, cap);
}

int32_t pc_bsphp_pay(const char* user, const char* user_pwd, const char* card,
                     char* out_json, size_t cap) {
  return pc_bsphp_call("chong.lg", "", out_json, cap);
}

int32_t pc_bsphp_notice(char* out_json, size_t cap) {
  return pc_bsphp_call("gg.in", "", out_json, cap);
}

int pc_bsphp_json_field(const char* json, const char* key, char* out,
                        size_t cap) {
  (void)json;
  (void)key;
  if (out != NULL && cap > 0) out[0] = '\0';
  return 0;
}

/* 心跳在非 Windows 上不可用（联网路径缺失）：单次与线程都回网络错误，
   采用会话空操作，避免调用方拿到假的「成功」。 */
int32_t pc_bsphp_heartbeat(char* out_json, size_t cap) {
  if (out_json != NULL && cap > 0) out_json[0] = '\0';
  return PC_ERR_NETWORK;
}

int pc_bsphp_adopt_session(const char* json) {
  (void)json;
  return 0;
}

/* 非 Windows：没有会话可维护，两个会话写入口都是空操作。 */
int pc_bsphp_adopt_session_ex(const char* api, const char* json) {
  (void)api;
  (void)json;
  return 0;
}

void pc_bsphp_clear_session(void) {}

/* 分级是纯逻辑（不碰网络 / 全局状态），非 Windows 上也照常可用 ——
   这样上层与单元测试在别的平台能拿到同一套判定。 */
int pc_bsphp_hb_classify(int32_t call_rc, const char* json) {
  int code = 0;

  if (call_rc != PC_OK) return PC_HB_TRANSIENT;
  if (json == NULL || !pc_bsphp_json_int(json, "code", &code)) {
    return PC_HB_TRANSIENT;
  }
  /* 这里不能调 bs_code_level（它是 _WIN32 分支里的 static），
     所以用公开的 pc_bsphp_session_dead 判 FATAL，其余按成功码/可继续处理。 */
  if (pc_bsphp_session_dead(code)) return PC_HB_FATAL;
  if (pc_bsphp_code_ok(code) == 1) return PC_HB_OK;
  return PC_HB_OK;
}

const char* pc_bsphp_hb_class_text(int level) {
  switch (level) {
    case PC_HB_OK:
      return "正常";
    case PC_HB_TRANSIENT:
      return "可恢复（不终止）";
    case PC_HB_FATAL:
      return "授权失效（终止）";
    default:
      return "未知";
  }
}

int32_t pc_bsphp_heartbeat_start(void) { return PC_ERR_NETWORK; }
int32_t pc_bsphp_heartbeat_stop(void) { return PC_OK; }
int32_t pc_bsphp_heartbeat_is_running(void) { return 0; }

#endif /* _WIN32 */
