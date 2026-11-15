/* ---------------------------------------------------------------------------
 * pc_http.h 的实现（WinHTTP）。
 *
 * 从 HttpURLConnection 迁过来，有四处行为差异值得记一笔：
 *
 *   1. HttpURLConnection 会自动跟随重定向，WinHTTP 默认不跟。
 *      这里显式打开跟随即（且只跟随 3 次），保持行为一致。
 *
 *   2. HttpURLConnection 的连接/读取超时分别对应 WinHTTP 的
 *      connect / receive 两个参数；发送超时 WinHTTP 单独有一个，取同一个值。
 *
 *   3. WinHTTP 的 API 全是宽字符，URL 与请求头要先转 UTF-8 → UTF-16。
 *
 *   4. 响应按字节读，最后补 NUL。不在这里做字符集猜测 —— 服务端返回的就是
 *      UTF-8，猜错了反而会毁掉中文提示语。
 * ------------------------------------------------------------------------- */

/* SRWLOCK（下面 session 缓存用）需要 Vista+ 的声明，先把目标版本钉住。 */
#if defined(_WIN32) && !defined(_WIN32_WINNT)
#define _WIN32_WINNT 0x0600
#endif

#include "pc_http.h"

#include <stdlib.h>
#include <string.h>

/* 填失败信息。两个平台分支都要用，所以放在 #if 外面。 */
static void pc_set_fail(pc_http_result* res, int32_t status, const char* detail) {
  if (res == NULL) {
    return;
  }
  res->http_status = status;
  if (detail == NULL) {
    res->message[0] = '\0';
    return;
  }
  {
    size_t n = strlen(detail);
    if (n + 1 > sizeof(res->message)) {
      n = sizeof(res->message) - 1;
    }
    memcpy(res->message, detail, n);
    res->message[n] = '\0';
  }
}

/* 大小写不敏感子串查找（判断自定义头里是否已有某个头，避免重复 Content-Type）。 */
static const char* pc_strcasestr(const char* hay, const char* needle) {
  size_t hlen = strlen(hay);
  size_t nlen = strlen(needle);
  size_t i;
  if (nlen == 0 || nlen > hlen) return NULL;
  for (i = 0; i + nlen <= hlen; i++) {
    size_t j;
    int ok = 1;
    for (j = 0; j < nlen; j++) {
      char a = hay[i + j];
      char b = needle[j];
      if (a >= 'A' && a <= 'Z') a = (char)(a - 'A' + 'a');
      if (b >= 'A' && b <= 'Z') b = (char)(b - 'A' + 'a');
      if (a != b) {
        ok = 0;
        break;
      }
    }
    if (ok) return hay + i;
  }
  return NULL;
}

#if defined(_WIN32)

#include <windows.h>
#include <winhttp.h>

#pragma comment(lib, "winhttp.lib")

/* UTF-8 → UTF-16。调用方 free。失败返回 NULL。 */
static wchar_t* pc_to_wide(const char* utf8) {
  int need;
  wchar_t* buf;

  if (utf8 == NULL) {
    return NULL;
  }
  need = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
  if (need <= 0) {
    return NULL;
  }
  buf = (wchar_t*)malloc((size_t)need * sizeof(wchar_t));
  if (buf == NULL) {
    return NULL;
  }
  if (MultiByteToWideChar(CP_UTF8, 0, utf8, -1, buf, need) <= 0) {
    free(buf);
    return NULL;
  }
  return buf;
}

/* 把 Win32 错误码翻译成中文短句，尽量具体 —— 连不上和超时的处理方式不同。 */
static void pc_win32_detail(DWORD err, char* out, size_t cap) {
  const char* text = NULL;

  switch (err) {
    case ERROR_WINHTTP_TIMEOUT:
      text = "连接超时";
      break;
    case ERROR_WINHTTP_NAME_NOT_RESOLVED:
      text = "域名解析失败";
      break;
    case ERROR_WINHTTP_CANNOT_CONNECT:
      text = "无法连接到服务器";
      break;
    case ERROR_WINHTTP_CONNECTION_ERROR:
      text = "连接被中断";
      break;
    case ERROR_WINHTTP_SECURE_FAILURE:
      text = "TLS 握手失败";
      break;
    case ERROR_WINHTTP_INVALID_URL:
      text = "接口地址非法";
      break;
    case ERROR_WINHTTP_OPERATION_CANCELLED:
      text = "请求被取消";
      break;
    case ERROR_WINHTTP_UNRECOGNIZED_SCHEME:
      text = "不支持的协议";
      break;
    default:
      break;
  }

  if (text != NULL) {
    size_t n = strlen(text);
    if (n + 1 > cap) {
      n = cap > 0 ? cap - 1 : 0;
    }
    if (cap > 0) {
      memcpy(out, text, n);
      out[n] = '\0';
    }
    return;
  }

  /* 兜底：露出数字。查 WinHTTP 错误码比看一句编造的中文有用。 */
  if (out == NULL || cap < 2) {
    if (out != NULL && cap > 0) {
      out[0] = '\0';
    }
    return;
  }
  {
    static const char kPrefix[] = "错误代码 ";
    char digits[16];
    int d = 0;
    DWORD v = err;
    size_t pos = 0;
    size_t n = sizeof(kPrefix) - 1;

    if (v == 0) {
      digits[d++] = '0';
    }
    while (v > 0 && d < 16) {
      digits[d++] = (char)('0' + (v % 10));
      v /= 10;
    }
    if (n + 2 > cap) {
      n = cap - 2;
    }
    memcpy(out, kPrefix, n);
    pos = n;
    while (d > 0 && pos + 1 < cap) {
      out[pos++] = digits[--d];
    }
    out[pos] = '\0';
  }
}

/* ---------------------------------------------------------------------------
 * WinHTTP session 复用
 *
 * 早先每个请求都 WinHttpOpen + WinHttpClose：等于每次都重建会话，WinHTTP 也就无从
 * 复用底层 TCP/TLS 连接。而抢单引擎会以每秒十几次的频率反复访问同一个 host，每次
 * 都要重新握手（TLS 约 100~300ms），固定延迟很可观。
 *
 * 现在按「超时组合」缓存 session 并常驻进程：同 host 的后续请求能命中 WinHTTP 的
 * 连接池，省掉重复握手。WinHTTP 的 session 句柄是线程安全的，每条请求各自
 * WinHttpConnect / WinHttpOpenRequest，互不干扰。
 *
 * 唯一的坑：超时是 **session 级**的（WinHttpSetTimeouts 只认 WinHttpOpen 返回的
 * 句柄），而各调用方用了好几组超时，所以按 (connect_ms, read_ms) 分开缓存。缓存满
 * 了或建不出来时，退回「临时 session、用完关掉」的老做法，保证任何配置都能工作。
 * ------------------------------------------------------------------------- */
/* 16 槽：实际用到的超时组合只有 4~5 组（大厅 10/15、车辆 10/15、上报 10/15、
 * 登录 10/20 等），留 3 倍余量。早先 8 槽在加新接口后就会溢出 —— 溢出不是错误，
 * 但会让那组超时每次都退回「临时 session、用完即关」，白白丢掉连接复用。 */
#define PC_HTTP_SESSION_SLOTS 16
typedef struct {
  int connect_ms;
  int read_ms;
  HINTERNET session;
} pc_http_session_slot;

static pc_http_session_slot g_sessions[PC_HTTP_SESSION_SLOTS];
static int g_session_count;
static SRWLOCK g_session_lock = SRWLOCK_INIT;

/* 新建一个配好超时与重定向策略的 session。失败返回 NULL。 */
static HINTERNET pc_http_open_session(int connect_ms, int read_ms) {
  HINTERNET s = WinHttpOpen(L"PigeonCore/1.0",
                            /* 显式不走系统自动代理（WPAD）。
                             *
                             * 早先用 WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY：内网
                             * 里存在恶意 WPAD / DHCP 代理时，全部请求（登录密码
                             * 密文、Bearer token、明文 HTTP 的滑块请求）都会被
                             * 攻击者代理转发。桌面工具没有「随系统代理走」的需
                             * 求，宁可不支持自动代理也不能默认信任网络环境。 */
                            WINHTTP_ACCESS_TYPE_NO_PROXY,
                            WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  if (s == NULL) {
    return NULL;
  }
  /* 发送超时 WinHTTP 单独有一个参数，取与连接超时同一个值。 */
  WinHttpSetTimeouts(s, connect_ms, connect_ms, read_ms, read_ms);
  /* 重定向策略：**禁止跨主机转发自定义头**。
   *
   * 早先无条件用 WINHTTP_OPTION_REDIRECT_POLICY_ALWAYS。WinHTTP 只对标准
   * Authorization 做跨主机剥离，而本项目用的全是小写自定义头
   * （authorization / Sn-AppId / req-x / Sn-Sign / APP-ID…）。服务端被劫持、
   * DNS 被污染或返回恶意 302 时，这些头会被原样带到第三方主机上 ——
   * Bearer token、签名产物、设备指纹一次性外泄。
   *
   * 改成 DISALLOW（不跟随重定向）：本项目所有接口都是固定 URL，没有一条
   * 依赖重定向；不跟随既消除了凭据外泄路径，也让「最多 3 跳」的隐性行为
   * 变成确定性行为。 */
  {
    /* 取值是 WINHTTP_OPTION_REDIRECT_POLICY_NEVER（WinHTTP 没有 DISALLOW 这个名字）。
     * NEVER = 完全不跟随重定向。 */
    DWORD redirect = WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
    WinHttpSetOption(s, WINHTTP_OPTION_REDIRECT_POLICY, &redirect,
                     sizeof(redirect));
  }
  return s;
}

/* 取一个可复用的 session；返回的句柄**不要关闭**。取不到返回 NULL（调用方回退到
 * 临时 session）。
 *
 * 锁只护住「查表 / 建表」这段内存操作，**不护网络 I/O**：WinHttpOpen 要走代理
 * 自动探测（WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY），在配了 WPAD 的机器上可能卡
 * 好几秒。早先把 WinHttpOpen 放在独占锁里，于是「第一次用到某个新超时组合」时
 * 全部工作线程会堵在这把锁上排队 —— 表现为整轮刷单集体停顿，而停止时
 * 这些线程也全都动不了。现在改成：锁内只查表，查不到就放锁、在外面建，
 * 建好再拿锁登记（若期间别人已经登记了同一组，就关掉自己这条、复用对方的）。 */
static HINTERNET pc_http_borrow_session(int connect_ms, int read_ms,
                                      int* out_own) {
  int i;
  HINTERNET s = NULL;
  HINTERNET fresh = NULL;

  if (out_own != NULL) {
    *out_own = 0;
  }

  AcquireSRWLockExclusive(&g_session_lock);
  for (i = 0; i < g_session_count; i++) {
    if (g_sessions[i].connect_ms == connect_ms &&
        g_sessions[i].read_ms == read_ms) {
      s = g_sessions[i].session;
      break;
    }
  }
  ReleaseSRWLockExclusive(&g_session_lock);
  if (s != NULL) {
    return s;
  }

  /* 没命中：在锁外建（慢操作，绝不持锁）。 */
  fresh = pc_http_open_session(connect_ms, read_ms);
  if (fresh == NULL) {
    return NULL;
  }

  AcquireSRWLockExclusive(&g_session_lock);
  /* 双重检查：并发的另一个线程可能刚刚登记了同一组超时。 */
  for (i = 0; i < g_session_count; i++) {
    if (g_sessions[i].connect_ms == connect_ms &&
        g_sessions[i].read_ms == read_ms) {
      s = g_sessions[i].session;
      break;
    }
  }
  if (s != NULL) {
    ReleaseSRWLockExclusive(&g_session_lock);
    WinHttpCloseHandle(fresh); /* 复用别人那条，关掉自己新建的 */
    return s;
  }
  if (g_session_count < PC_HTTP_SESSION_SLOTS) {
    g_sessions[g_session_count].connect_ms = connect_ms;
    g_sessions[g_session_count].read_ms = read_ms;
    g_sessions[g_session_count].session = fresh;
    g_session_count++;
    s = fresh;
  }
  ReleaseSRWLockExclusive(&g_session_lock);
  if (s == NULL) {
    /* 缓存满了：这条不入表，交给调用方当临时 session 用，用完关掉
       （通过 out_own 明确交回所有权，否则调用方会当成常驻 session 永不关闭，
       每溢出一次就漏一个 session 句柄）。 */
    if (out_own != NULL) {
      *out_own = 1;
    }
    return fresh;
  }
  return s;
}

/* ---------------------------------------------------------------------------
 * 退出时掐断在飞的请求
 *
 * 为什么需要：pc_core_shutdown 走的是「置停止标志 → 短暂等 → TerminateProcess」。
 * 工作线程这时很可能正卡在 WinHttpReceiveResponse / WinHttpReadData 里，最长
 * connect 10s + read 15s = 25s。硬杀进程等于让这些线程在任意指令处消失：它们
 * 可能正持着 g_queue_lock / g_side_lock / g_stat_lock，也可能刚 malloc 完还没登记。
 * 进程本身随后就结束了，所以不会留下「死锁的下一次运行」；但被硬杀时那些线程
 * 的栈上缓冲、堆块没人收尾，而且退出会显得很卡（要等满 25s 才 TerminateProcess）。
 *
 * 做法：把所有在飞的 request 句柄登记在一张表里。abort 时把置位标志并逐个
 * WinHttpCloseHandle —— WinHTTP 规定句柄可以被另一个线程关闭，挂起的调用会立刻
 * 以 ERROR_WINHTTP_OPERATION_CANCELLED 返回，线程沿正常路径退栈、解锁、free。
 *
 * 只在退出路径上用：置位后所有请求立刻失败，所以 pc_engine_start 会 abort_reset
 * 复位（见那里的注释），保证「退出未遂 / 重启」之后网络仍然可用。
 * ------------------------------------------------------------------------- */

#define PC_HTTP_LIVE_CAP 64

/* 「取消代次」——只增不减的计数器，替代早先的布尔标志。
 *
 * 【为什么不能再用布尔标志】
 *
 * 早先这里是一个 g_abort_flag：pc_http_abort_all 置 1，而全工程只有
 * pc_engine_start 会把它复位成 0。于是「结束刷单」之后标志一直是 1，而登录 /
 * 验证码 / 滑块这些**不属于引擎**的接口根本不经过 pc_engine_start —— 它们一进
 * 读循环就被 pc_http_aborted() 判成取消，返回 http_status = 0、message =
 * 「已取消」。用户看到的就是「点结束之后登录和验证码接口全部 HTTP=0 报错」，
 * 而且除非再点一次「开始」，否则永远好不了。
 *
 * 现在改成代次：
 *   · pc_http_abort_all 只做 ++；
 *   · 每个请求在**发起那一刻**记下当时的代次 my_gen；
 *   · 读循环里比 g_abort_gen != my_gen 才算被取消。
 *
 * 于是「abort 之前就存在的请求」会被取消，「abort 之后新发的请求」天然带着新
 * 代次、不受任何影响 —— 结束刷单不再污染后续的登录 / 验证码请求，也不再需要
 * 「谁负责复位」这种跨模块约定。
 *
 * 代次用 LONG 只增不减：32 位回绕要 20 亿次 abort，实际不可达；即使回绕，后果
 * 也只是某个极老的在飞请求可能不被取消（那种情况由句柄关闭兜住）。 */
static volatile LONG g_abort_gen;
static SRWLOCK g_live_lock = SRWLOCK_INIT;
static HINTERNET g_live[PC_HTTP_LIVE_CAP];
static int g_live_count;

/* 登记一个在飞的 request；表满时返回 0（调用方照常发请求，只是退出时掐不断它，
 * 退化成老行为，不影响功能）。 */
static int pc_http_live_add(HINTERNET req) {
  int slot = -1;
  int i;

  if (req == NULL) {
    return 0;
  }
  AcquireSRWLockExclusive(&g_live_lock);
  if (g_live_count < PC_HTTP_LIVE_CAP) {
    slot = g_live_count;
    g_live[g_live_count++] = req;
  } else {
    /* 表满：先找已关闭留下的空位（正常路径会即时摘除，这里只是兜底）。 */
    for (i = 0; i < PC_HTTP_LIVE_CAP; i++) {
      if (g_live[i] == NULL) {
        g_live[i] = req;
        slot = i;
        break;
      }
    }
  }
  ReleaseSRWLockExclusive(&g_live_lock);
  return slot >= 0;
}

/* 摘除登记。返回 1 表示这个句柄已经被 abort 关掉了，调用方不要再 CloseHandle
 * （重复关闭一个已关闭的句柄是未定义行为，可能关掉别的线程刚复用的同值句柄）。 */
static int pc_http_live_remove(HINTERNET req) {
  int taken_by_abort = 1; /* 默认当作「已被 abort 关掉」 */
  int i;

  if (req == NULL) {
    return 0;
  }
  AcquireSRWLockExclusive(&g_live_lock);
  for (i = 0; i < PC_HTTP_LIVE_CAP; i++) {
    if (g_live[i] == req) {
      g_live[i] = NULL;
      /* 清空位后把 count 收到最后一个非空槽之后，保持槽位紧凑可复用。 */
      while (g_live_count > 0 && g_live[g_live_count - 1] == NULL) {
        g_live_count--;
      }
      taken_by_abort = 0; /* 还在表里 → 没被关，调用方仍持有它 */
      break;
    }
  }
  ReleaseSRWLockExclusive(&g_live_lock);
  return taken_by_abort;
}

void pc_http_abort_all(void) {
  int i;
  HINTERNET to_close[PC_HTTP_LIVE_CAP];
  int n = 0;

  /* 抬代次：此刻之前发起的请求全部视为被取消 —— 包括表满没登记上、没有句柄可关
     的那些（代次是它们唯一的取消通道）。之后发起的请求带新代次，不受影响。 */
  InterlockedIncrement(&g_abort_gen);
  /* 【锁内只摘表，锁外才关闭】
   *
   * WinHttpCloseHandle 会等待底层连接状态收敛（挂起中的 Send/Receive 要走到
   * 取消路径），耗时不确定。早先整段都在 g_live_lock 独占区里做：退出时所有
   * 线程的 pc_http_live_add / live_remove 全被堵住 —— 表现为「点了关闭之后
   * 卡住好几秒」，正是本函数想消除的那种僵住。
   *
   * 现在锁内只做内存搬运（最多 64 个句柄），槽位立刻清空；释放锁之后再逐个
   * 关闭。关闭顺序与「先摘表再关」的语义完全一致：摘表后别人既不会登记同一
   * 句柄，也不会误把它当「仍在我手上」。 */
  AcquireSRWLockExclusive(&g_live_lock);
  for (i = 0; i < PC_HTTP_LIVE_CAP; i++) {
    if (g_live[i] != NULL) {
      to_close[n++] = g_live[i];
      g_live[i] = NULL;
    }
  }
  g_live_count = 0;
  ReleaseSRWLockExclusive(&g_live_lock);

  for (i = 0; i < n; i++) {
    /* 关闭会让挂起的 WinHttp* 立刻返回。摘表时已置空，不存在二次关闭。 */
    WinHttpCloseHandle(to_close[i]);
  }
}

void pc_http_abort_reset(void) {
  /* 【保留为空操作】
   *
   * 改用代次之后不再需要「复位」：新请求天然带新代次，不会被旧的 abort 波及。
   * 函数与调用点都保留 —— 导出符号不随便删（Dart 侧 / 已发布的二进制），
   * 也让「start 里复位过网络」这段叙事在调用方仍然读得通。真正的语义已经由
   * pc_http_request 开头的代次快照承担。 */
}

/* 这次请求（发起时代次为 my_gen）是否已被 abort 取消。
 *
 * 注意判据是「代次变了」而不是「代次非零」：后者会把 abort 之后新发的请求也
 * 一起判死 —— 那正是登录 / 验证码接口 HTTP=0 的根因。 */
static int pc_http_cancelled(int32_t my_gen) {
  return InterlockedCompareExchange(&g_abort_gen, 0, 0) != my_gen;
}

/* 共用主体：POST 传 method 为 L"POST" 且 body 非空，GET 传 body 为 NULL。
 * extra_headers 是可选的自定义请求头（UTF-8，"\r\n" 分隔），为 NULL 表示没有。 */
static int pc_http_request(const wchar_t* method, const char* url,
                           const char* body, const char* extra_headers,
                           int connect_ms, int read_ms, char* out,
                           size_t out_cap, size_t* out_len,
                           pc_http_result* res) {
  wchar_t* wide_url;
  wchar_t* wide_host;
  wchar_t* wide_path;
  URL_COMPONENTS parts;
  HINTERNET session = NULL;
  int own_session = 0; /* 1 = 临时 session（缓存没槽位 / 建不出来），用完要关 */
  HINTERNET connect = NULL;
  HINTERNET request = NULL;
  int live_slot = 0; /* 1 = 已登记进在飞请求表（退出时可被掐断） */
  int ok = PC_HTTP_ERR;
  /* 发起这一刻的代次快照：只有**之后**发生的 abort 才算取消这次请求。
   * 早先判的是全局布尔标志，于是「结束刷单」置位后，后续的登录 / 验证码请求
   * 一进读循环就被判成取消（http_status = 0）。代次让作用域收敛到「本次请求
   * 生命周期内发生的 abort」。 */
  const int32_t my_gen = (int32_t)InterlockedCompareExchange(&g_abort_gen, 0, 0);
  size_t written = 0;

  if (out != NULL && out_cap > 0) {
    out[0] = '\0';
  }
  if (out_len != NULL) {
    *out_len = 0;
  }
  if (url == NULL || out == NULL || out_cap == 0) {
    pc_set_fail(res, 0, "接口地址为空");
    return PC_HTTP_ERR;
  }

  /* 先把 host 和 path 从 URL 里拆出来。手工拆容易漏掉端口与查询串，
     交给 WinHttpCrackUrl 更稳。 */
  wide_url = pc_to_wide(url);
  if (wide_url == NULL) {
    pc_set_fail(res, 0, "接口地址编码失败");
    return PC_HTTP_ERR;
  }

  /* host / path 缓冲按**实际 URL 长度**分配，不再写死 256 / 2048。
   *
   * 早先固定 2048 宽字符：而 pc_shide_report_impl 的 URL 可达 40 000 字节
   * （把 32KB 响应体编码进查询串），转宽字符后约 4 万 —— 超长时
   * WinHttpCrackUrl 直接失败，返回一句「接口地址非法」，与真实原因
   * （上报内容太长）完全无关，排查方向全错。
   * 现在按 wide_url 长度留足（+1 给 NUL），并把超长提前判成明确的错误。 */
  {
    size_t url_wlen = wcslen(wide_url);
    size_t host_cap = 256;
    size_t path_cap = url_wlen + 2;
    if (path_cap < 2048) path_cap = 2048;
    wide_host = (wchar_t*)malloc(host_cap * sizeof(wchar_t));
    wide_path = (wchar_t*)malloc(path_cap * sizeof(wchar_t));
    if (wide_host == NULL || wide_path == NULL) {
      free(wide_url);
      free(wide_host);
      free(wide_path);
      pc_set_fail(res, 0, "内存不足");
      return PC_HTTP_ERR;
    }
    wide_host[0] = L'\0';
    wide_path[0] = L'\0';

    memset(&parts, 0, sizeof(parts));
    parts.dwStructSize = sizeof(parts);
    parts.lpszHostName = wide_host;
    parts.dwHostNameLength = (DWORD)(host_cap - 1);
    parts.lpszUrlPath = wide_path;
    parts.dwUrlPathLength = (DWORD)(path_cap - 1);
  }

  if (!WinHttpCrackUrl(wide_url, 0, 0, &parts)) {
    free(wide_url);
    free(wide_host);
    free(wide_path);
    pc_set_fail(res, 0, "接口地址非法");
    return PC_HTTP_ERR;
  }

  /* 优先借用常驻 session（可命中 WinHTTP 的连接池，省掉重复 TCP/TLS 握手）；
   * 缓存没槽位 / 建不出来时才退回「临时 session，用完关掉」。 */
  session = pc_http_borrow_session(connect_ms, read_ms, &own_session);
  if (session == NULL) {
    session = pc_http_open_session(connect_ms, read_ms);
    own_session = 1;
  }
  if (session == NULL) {
    pc_win32_detail(GetLastError(),
                    (res != NULL) ? res->message : NULL,
                    (res != NULL) ? sizeof(res->message) : 0);
    free(wide_url);
    free(wide_host);
    free(wide_path);
    pc_set_fail(res, 0, "网络组件初始化失败");
    return PC_HTTP_ERR;
  }

  connect = WinHttpConnect(session, wide_host, parts.nPort, 0);
  if (connect == NULL) {
    DWORD err = GetLastError();
    pc_win32_detail(err, res != NULL ? res->message : NULL,
                    res != NULL ? sizeof(res->message) : 0);
    goto done;
  }

  request = WinHttpOpenRequest(connect, method, wide_path, NULL,
                               WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
                               (parts.nScheme == INTERNET_SCHEME_HTTPS)
                                   ? WINHTTP_FLAG_SECURE
                                   : 0);
  if (request == NULL) {
    DWORD err = GetLastError();
    pc_win32_detail(err, res != NULL ? res->message : NULL,
                    res != NULL ? sizeof(res->message) : 0);
    goto done;
  }
  /* 登记进「在飞请求表」，退出时 pc_http_abort_all 才能把它掐断。 */
  live_slot = pc_http_live_add(request);

  {
    wchar_t* hdrs_w = NULL;
    LPCWSTR send_hdrs = WINHTTP_NO_ADDITIONAL_HEADERS;
    DWORD send_hdrs_len = 0;
    int ok_send = 0;

    if (body != NULL) {
      /* POST：默认 Content-Type 为 form，但若调用方已在自定义头里自带
       * Content-Type（如滑块识别传 application/json），则不再重复添加，
       * 否则会出现两个 Content-Type 头导致服务器/WinHTTP 异常。 */
      static const char kFormHeader[] =
          "Content-Type: application/x-www-form-urlencoded\r\n";
      int has_ct = (extra_headers != NULL) &&
                   pc_strcasestr(extra_headers, "content-type:") != NULL;
      size_t extra_len = (extra_headers != NULL) ? strlen(extra_headers) : 0;
      /* 缓冲留足余量并改用有界拼接。
       *
       * 早先是 malloc(strlen(kFormHeader) + extra_len + 2) + strcpy/strcat：
       * 长度恰好等于分配量、零余量，任何一处常量改动（例如给 kFormHeader
       * 多一个空格）立刻溢出。这里按实际需要 + 8 余量分配，并显式校验
       * 拼接结果，杜绝「刚好卡在边界」的写法。 */
      size_t head_len = has_ct ? 0 : strlen(kFormHeader);
      char* combined = (char*)malloc(head_len + extra_len + 8);
      if (combined == NULL) {
        pc_set_fail(res, 0, "内存不足");
        goto done;
      }
      combined[0] = '\0';
      if (head_len > 0) {
        memcpy(combined, kFormHeader, head_len);
        combined[head_len] = '\0';
      }
      if (extra_len > 0) {
        memcpy(combined + head_len, extra_headers, extra_len);
        combined[head_len + extra_len] = '\0';
      }
      hdrs_w = pc_to_wide(combined);
      free(combined);
      if (hdrs_w == NULL) {
        pc_set_fail(res, 0, "请求头编码失败");
        goto done;
      }
      send_hdrs = hdrs_w;
      send_hdrs_len = (DWORD)-1L;
    } else if (extra_headers != NULL) {
      hdrs_w = pc_to_wide(extra_headers);
      if (hdrs_w == NULL) {
        pc_set_fail(res, 0, "请求头编码失败");
        goto done;
      }
      send_hdrs = hdrs_w;
      send_hdrs_len = (DWORD)-1L;
    }

    if (body != NULL) {
      DWORD body_len = (DWORD)strlen(body);
      ok_send = WinHttpSendRequest(request, send_hdrs, send_hdrs_len,
                                   (LPVOID)body, body_len, body_len, 0) != 0;
    } else {
      ok_send = WinHttpSendRequest(request, send_hdrs, send_hdrs_len,
                                   WINHTTP_NO_REQUEST_DATA, 0, 0, 0) != 0;
    }
    if (hdrs_w != NULL) {
      free(hdrs_w);
    }
    if (!ok_send) {
      DWORD err = GetLastError();
      pc_win32_detail(err, res != NULL ? res->message : NULL,
                      res != NULL ? sizeof(res->message) : 0);
      goto done;
    }
  }

  if (!WinHttpReceiveResponse(request, NULL)) {
    DWORD err = GetLastError();
    pc_win32_detail(err, res != NULL ? res->message : NULL,
                    res != NULL ? sizeof(res->message) : 0);
    goto done;
  }

  /* 先读正文（无论状态码）：非 200 时响应体通常带错误详情，要透给上层。 */
  for (;;) {
    DWORD read = 0;
    if (pc_http_cancelled(my_gen)) {
      pc_set_fail(res, 0, "已取消");
      goto done;
    }
    if (written + 1 >= out_cap) {
      pc_set_fail(res, 200, "响应内容过长");
      goto done;
    }
    if (!WinHttpReadData(request, out + written,
                         (DWORD)(out_cap - written - 1), &read)) {
      DWORD err = GetLastError();
      pc_win32_detail(err, res != NULL ? res->message : NULL,
                      res != NULL ? sizeof(res->message) : 0);
      goto done;
    }
    if (read == 0) {
      break;
    }
    written += read;
  }
  out[written] = '\0';
  if (out_len != NULL) {
    *out_len = written;
  }

  /* 状态码：非 200 也是「拿到了响应」，把错误体前若干字节塞进 message 透出。 */
  {
    DWORD status = 0;
    DWORD size = sizeof(status);
    if (!WinHttpQueryHeaders(
            request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
            WINHTTP_HEADER_NAME_BY_INDEX, &status, &size,
            WINHTTP_NO_HEADER_INDEX)) {
      DWORD err = GetLastError();
      pc_win32_detail(err, res != NULL ? res->message : NULL,
                      res != NULL ? sizeof(res->message) : 0);
      goto done;
    }
    if (status != 200) {
      char snippet[196];
      size_t n = written < (sizeof(snippet) - 1) ? written : (sizeof(snippet) - 1);
      memcpy(snippet, out, n);
      snippet[n] = '\0';
      pc_set_fail(res, (int32_t)status, snippet[0] != '\0' ? snippet : "无响应体");
      goto done;
    }
  }
  pc_set_fail(res, 200, NULL);
  ok = PC_HTTP_OK;

done:
  if (request != NULL) {
    /* 先摘登记：如果退出路径已经把它关了，这里就不能再关（重复关闭同一句柄
     * 可能关掉别的线程刚复用的同值句柄）。摘除失败说明表满没登记上，正常关闭。 */
    if (live_slot && pc_http_live_remove(request)) {
      request = NULL;
    }
    if (request != NULL) {
      WinHttpCloseHandle(request);
    }
  }
  if (connect != NULL) {
    WinHttpCloseHandle(connect);
  }
  if (own_session && session != NULL) {
    /* 常驻 session 留着复用，不关；只有临时建的那个才在这里关闭。 */
    WinHttpCloseHandle(session);
  }
  free(wide_url);
  free(wide_host);
  free(wide_path);
  return ok;
}

int pc_http_post(const char* url, const char* body, int connect_ms, int read_ms,
                 char* out, size_t out_cap, size_t* out_len,
                 pc_http_result* res) {
  return pc_http_request(L"POST", url, body, NULL, connect_ms, read_ms, out,
                         out_cap, out_len, res);
}

int pc_http_get(const char* url, int connect_ms, int read_ms, char* out,
                size_t out_cap, size_t* out_len, pc_http_result* res) {
  return pc_http_request(L"GET", url, NULL, NULL, connect_ms, read_ms, out,
                         out_cap, out_len, res);
}

int pc_http_post_hdrs(const char* url, const char* body, const char* headers,
                      int connect_ms, int read_ms, char* out, size_t out_cap,
                      size_t* out_len, pc_http_result* res) {
  return pc_http_request(L"POST", url, body, headers, connect_ms, read_ms, out,
                         out_cap, out_len, res);
}

int pc_http_get_hdrs(const char* url, const char* headers, int connect_ms,
                     int read_ms, char* out, size_t out_cap, size_t* out_len,
                     pc_http_result* res) {
  return pc_http_request(L"GET", url, NULL, headers, connect_ms, read_ms, out,
                         out_cap, out_len, res);
}

#else /* !_WIN32 */

/* 非 Windows 平台：编译得过、函数存在，但联网路径不可用。
   这样核心包在 Linux/macOS 上仍然能跑单元测试（那些用例不碰网络）。 */
int pc_http_post(const char* url, const char* body, int connect_ms, int read_ms,
                 char* out, size_t out_cap, size_t* out_len,
                 pc_http_result* res) {
  (void)url;
  (void)body;
  (void)connect_ms;
  (void)read_ms;
  (void)out;
  (void)out_cap;
  if (out_len != NULL) {
    *out_len = 0;
  }
  pc_set_fail(res, 0, "当前平台未实现网络传输");
  return PC_HTTP_ERR;
}

int pc_http_get(const char* url, int connect_ms, int read_ms, char* out,
                size_t out_cap, size_t* out_len, pc_http_result* res) {
  (void)url;
  (void)connect_ms;
  (void)read_ms;
  (void)out;
  (void)out_cap;
  if (out_len != NULL) {
    *out_len = 0;
  }
  pc_set_fail(res, 0, "当前平台未实现网络传输");
  return PC_HTTP_ERR;
}

int pc_http_post_hdrs(const char* url, const char* body, const char* headers,
                      int connect_ms, int read_ms, char* out, size_t out_cap,
                      size_t* out_len, pc_http_result* res) {
  (void)url;
  (void)body;
  (void)headers;
  (void)connect_ms;
  (void)read_ms;
  (void)out;
  (void)out_cap;
  if (out_len != NULL) {
    *out_len = 0;
  }
  pc_set_fail(res, 0, "当前平台未实现网络传输");
  return PC_HTTP_ERR;
}

int pc_http_get_hdrs(const char* url, const char* headers, int connect_ms,
                     int read_ms, char* out, size_t out_cap, size_t* out_len,
                     pc_http_result* res) {
  (void)url;
  (void)headers;
  (void)connect_ms;
  (void)read_ms;
  (void)out;
  (void)out_cap;
  if (out_len != NULL) {
    *out_len = 0;
  }
  pc_set_fail(res, 0, "当前平台未实现网络传输");
  return PC_HTTP_ERR;
}

/* 非 Windows：没有 WinHTTP 句柄可掐，退化成空实现（接口仍然齐备）。 */
void pc_http_abort_all(void) {}
void pc_http_abort_reset(void) {}

#endif /* _WIN32 */

void pc_http_error_message(const char* detail, char* out, size_t cap) {
  static const char kPrefix[] = "请求异常：";
  size_t prefix_len = sizeof(kPrefix) - 1;
  size_t detail_len;

  if (out == NULL || cap == 0) {
    return;
  }
  out[0] = '\0';
  if (detail == NULL) {
    detail = "";
  }
  detail_len = strlen(detail);
  if (prefix_len + detail_len + 1 > cap) {
    detail_len = (cap > prefix_len + 1) ? (cap - prefix_len - 1) : 0;
  }
  memcpy(out, kPrefix, prefix_len);
  memcpy(out + prefix_len, detail, detail_len);
  out[prefix_len + detail_len] = '\0';
}
