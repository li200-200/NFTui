/* ---------------------------------------------------------------------------
 * HTTP 传输层 —— 对应 Kotlin 版里 HttpURLConnection 那一段。
 *
 * 为什么不用 libcurl：本工作区不做交叉编译，目标就是 Windows 桌面，
 * 而 WinHTTP 是系统自带的，不需要引入第三方库、不需要额外配置链接路径
 * （.c 里用 #pragma comment(lib, "winhttp.lib") 自己把库挂上）。
 *
 * 非 Windows 平台编译时下面的函数会直接返回失败，保证核心包在别的平台上
 * 仍然能编译、能跑单元测试（只有联网那几条路径不可用）。
 * ------------------------------------------------------------------------- */

#ifndef PC_HTTP_H
#define PC_HTTP_H

#include <stddef.h>
#include <stdint.h>

/* 一次请求的失败信息，给上层拼提示语用。 */
typedef struct {
  /* 0 = 没走到 HTTP 层（DNS / 连接 / 超时等），此时看 message。 */
  int32_t http_status;
  char message[192];
} pc_http_result;

/* 结果码：0 = 成功拿到 200 响应，其余为失败。 */
#define PC_HTTP_OK 0
#define PC_HTTP_ERR (-1)

/* POST application/x-www-form-urlencoded。
   - url           完整 URL
   - body          表单正文（UTF-8）
   - connect_ms    DNS + 连接超时
   - read_ms       发送 / 接收超时
   - out/out_cap   响应正文写这里，始终 NUL 结尾
   - out_len       实际写入的字节数（不含结尾 NUL），可为 NULL
   - res           失败明细，可为 NULL

   返回 PC_HTTP_OK / PC_HTTP_ERR。注意「HTTP 404」属于拿到了响应，
   这里返回 PC_HTTP_ERR 并把 http_status 填成 404，由上层决定要不要换线路。 */
int pc_http_post(const char* url, const char* body, int connect_ms, int read_ms,
                 char* out, size_t out_cap, size_t* out_len,
                 pc_http_result* res);

/* GET，语义同上（公告接口用它）。 */
int pc_http_get(const char* url, int connect_ms, int read_ms, char* out,
                size_t out_cap, size_t* out_len, pc_http_result* res);

/* 带自定义请求头的 POST。headers 是 UTF-8，各头以 "\r\n" 分隔（可不含结尾
 * CRLF）；为 NULL 时等价于 pc_http_post。Content-Type 固定为
 * application/x-www-form-urlencoded（与 pc_http_post 一致）。Shide 登录等
 * 需要 authorization / sn-appid 这类头的接口用它。 */
int pc_http_post_hdrs(const char* url, const char* body, const char* headers,
                      int connect_ms, int read_ms, char* out, size_t out_cap,
                      size_t* out_len, pc_http_result* res);

/* 带自定义请求头的 GET，headers 同上；为 NULL 时等价于 pc_http_get。 */
int pc_http_get_hdrs(const char* url, const char* headers, int connect_ms,
                     int read_ms, char* out, size_t out_cap, size_t* out_len,
                     pc_http_result* res);

/* 拼一个可读的失败描述，形如「请求异常：超时」。
   对应 Kotlin 里 `"请求异常：" + errMsg(e.message)` 那段。 */
void pc_http_error_message(const char* detail, char* out, size_t cap);

/* 进程退出前的「掐断在飞的请求」开关。
 *
 * 退出时如果只是 TerminateProcess，工作线程可能正停在 WinHttpReceiveResponse 里
 * 长达 25s，进程被硬杀时它们的栈/堆状态没人收尾。pc_core_shutdown 会先调用
 * pc_http_abort_all()，把当前登记在案的 request 句柄从别的线程关掉 ——
 * WinHTTP 会立刻让挂起的调用以 ERROR_WINHTTP_OPERATION_CANCELLED 返回，
 * 线程得以沿正常路径退栈、解锁、释放内存，进程随后才被结束。
 *
 * 【作用域只覆盖「此刻已经在飞的请求」】
 *
 * 实现抬的是一个只增不减的「取消代次」：每个请求在发起那一刻记下当时的代次，
 * 只有代次在自己生命周期内变过才算被取消。所以 abort 之后新发起的请求（登录、
 * 取验证码、拉滑块……）天然免疫，不需要任何人去「复位」。
 *
 * 早先用的是全局布尔标志，只有 pc_engine_start 会复位 —— 于是「点结束」之后
 * 所有不经过引擎启动的接口全部返回 http_status=0 / 「已取消」，除非再点一次
 * 「开始」否则永远好不了。这是代次方案要解决的问题。
 *
 * pc_http_abort_reset 保留为空操作：导出符号稳定，调用点也留着当语义锚点。 */
void pc_http_abort_all(void);
void pc_http_abort_reset(void);

#endif /* PC_HTTP_H */
