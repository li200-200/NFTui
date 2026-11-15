/* ---------------------------------------------------------------------------
 * BSPHP 网络验证客户端（登录模式 .lg）
 *
 * 对齐 BSPHP-C-DEMO-LOGIN\main.c 的调用流程：
 *   1) bootstrap              握手（internet.in + BSphpSeSsL.in）拿会话串
 *   2) registrationaska.lg    卡注册账号（kaid=卡号/激活码，kapwd=卡密）
 *   3) login.lg               账号登录（user/pwd/coode/key/maxoror）
 *   4) chong.lg               软件充值 / VIP 续期（userset=1）
 *   5) gg.in                  取软件公告
 *
 * 协议要点（与 demo 的 bsphp_client.c 一一对应）：
 *   请求：MD5 握手串 -> AES-128-CBC(密钥=MD5(私钥+appsafecode)前16位, IV=密钥)
 *         -> 密文再包一层 "0|AES-128-CBC|key|MD5(密文)|json"
 *         -> 用客户端公钥 RSA-PKCS1 加密 -> 拼 "密文|签名" -> 百分号编码
 *         -> POST parameter=... 到 AppEn.php
 *   响应：URL 解码 -> 按 '|' 拆三段 -> RSA 私钥解出响应 AES key -> AES 解出 JSON
 *
 * 只依赖 pc_http（WinHTTP）与 BCrypt/CAPI，非 Windows 为空实现。
 * ------------------------------------------------------------------------- */

#ifndef PC_BSPHP_H
#define PC_BSPHP_H

#include <stddef.h>
#include <stdint.h>

/* 覆盖配置。四项都可以为 NULL（按内置默认处理）。
   上线前请换成你自己后台的：接口地址(appid/m)、通信 key、服务端私钥、客户端公钥。 */
void pc_bsphp_configure(const char* api_url, const char* mutual_key,
                        const char* server_priv_b64, const char* client_pub_b64);

/* 初始化握手：internet.in + BSphpSeSsL.in，取回会话串（后续接口都要带）。
 * 已握过手再调用会重新握手。返回 PC_OK / PC_ERR_NETWORK / PC_ERR_SERVER。 */
int32_t pc_bsphp_bootstrap(void);

/* 与上面相同，但**持有全进程唯一的握手锁**。
 *
 * 所有「不是在 pc_auth_bsphp_ensure() 里」的握手都必须走这个入口
 * （目前只有心跳自愈）。否则两轮握手并发、各建一条匿名会话互相覆盖，
 * 且 pc_auth_bsphp_reset() 的清零会被反向覆盖，「会话自愈」永久失效。 */
int32_t pc_bsphp_bootstrap_serialized(void);

/* 通用调用。api 形如 "login.lg"，extra 形如 "user=a&pwd=b"（可 NULL/空）。
 * out_json 收到的是**解密后的响应 JSON**（有界、始终 NUL 结尾）。
 * 返回 PC_OK / PC_ERR_NETWORK / PC_ERR_SERVER。 */
int32_t pc_bsphp_call(const char* api, const char* extra, char* out_json,
                      size_t cap);

/* ---- main.c 里的四个业务接口 ---- */

/* 3) 登录：login.lg。machine 为机器码（同时作为 key 与 maxoror）。 */
int32_t pc_bsphp_login(const char* user, const char* pwd, const char* machine,
                       char* out_json, size_t cap);

/* 2) 卡注册：registrationaska.lg。card 为卡号/激活码（kaid），卡密留空。 */
int32_t pc_bsphp_register_by_card(const char* user, const char* pwd,
                                  const char* card, const char* machine,
                                  char* out_json, size_t cap);

/* 5) 充值 / VIP 续期：chong.lg（userset=1）。user_pwd 为账号密码（页面没有该
 *    输入框时传空串，服务端若强制校验再补字段）。 */
int32_t pc_bsphp_pay(const char* user, const char* user_pwd, const char* card,
                     char* out_json, size_t cap);

/* 取软件公告：gg.in。 */
int32_t pc_bsphp_notice(char* out_json, size_t cap);

/* 登录心跳：timeout.lg（无额外参数，用当前会话串保活 / 更新在线状态）。 */
int32_t pc_bsphp_heartbeat(char* out_json, size_t cap);

/* 采用业务响应里的新会话串：**按接口白名单**。
 *
 * 只有真正建立登录态的接口（login.lg / chong.lg）才允许把响应里的 `SeSsL`
 * 写进全局会话。原因：服务端每个响应都回显 session_id()，所以「响应里有
 * SeSsL」不等于「这条会话带登录态」—— 握手（internet.in / BSphpSeSsL.in）、
 * 公告（gg.in）、卡注册（registrationaska.lg）回的都是**匿名会话**，一旦写进去
 * 就会顶掉登录会话，下一次 timeout.lg 被服务端判为「未登录(1049)」。
 *
 * api 为本次调用的接口名（如 "login.lg"）。白名单外返回 0，不写。
 * 采用成功返回 1。 */
int pc_bsphp_adopt_session_ex(const char* api, const char* json);

/* 兼容旧签名：**不再无差别采用**，一律返回 0（fail-closed）。
 * 保留符号只为不破坏既有调用方；新代码请用 pc_bsphp_adopt_session_ex。 */
int pc_bsphp_adopt_session(const char* json);

/* 显式作废当前会话（会话自愈 / 退出登录）。
 *
 * bootstrap 不再「先清空再握手」（那会制造空会话窗口期，让并发的心跳打
 * timeout.lg 拿到 1049）。需要让旧会话失效时，由调用方显式调这里。 */
void pc_bsphp_clear_session(void);

/* ---- 心跳失败分级（三级） ----
 *
 * 心跳不是「成功 / 失败」二元判断。服务端用同一张码表表达三种完全不同的
 * 情况，混在一起处理就会出现「一次网络抖动就把整个程序关掉」的自杀行为。
 *
 *   PC_HB_OK        成功（或该码不代表任何问题）。继续下一周期。
 *   PC_HB_TRANSIENT 可自愈的失败。**绝不结束进程**：
 *                   本地会话问题（1049 未登录 / 5027 状态更新失败）→ 先重握手
 *                   再试一次；网络失败 / 响应解不开 / 缺 code / 表外未知码 →
 *                   下轮再判。
 *   PC_HB_FATAL     真·授权失效。冻结 / 到期 / 被顶号 / 账号级超时 /
 *                   **在线数超限**，继续运行无意义 → 结束进程。
 *
 * 判定入口是 pc_bsphp_hb_classify()，纯函数，不碰网络，便于单元测试。 */
#define PC_HB_OK 0
#define PC_HB_TRANSIENT 1
#define PC_HB_FATAL 2

/* 心跳失败分级：把「一次 timeout.lg 调用的结果」折成上面三个等级。
 *
 * call_rc 是 pc_bsphp_heartbeat 的返回值（PC_OK / PC_ERR_NETWORK / ...），
 * json 是解密后的响应（可为空串）。两者合起来才够判断 —— 只拿 code 判会把
 * 网络失败误当业务失败，只拿 call_rc 判又会漏掉服务端明确说的「你到期了」。
 *
 * 纯函数：无网络、无全局状态读写，可任意并发调用。 */
int pc_bsphp_hb_classify(int32_t call_rc, const char* json);

/* 分级对应的中文说明（用于日志 / 界面提示）。永不返回 NULL。 */
const char* pc_bsphp_hb_class_text(int level);

/* ---- 心跳循环线程（每 10 分钟一次 timeout.lg） ----
 *
 * 这是本模块唯一的后台线程，属 ABI 契约「不阻塞、不起线程」的**显式例外**
 * （与抢单引擎同类）：登录成功进入工作台后由界面调用 start 起一个循环线程，
 * 离开时 stop。stop 是协作式的：只置停止标志、唤醒等待，**立即返回**，
 * 线程自己退；界面可轮询 is_running 确认已收干净。
 *
 * 门禁按三级处理（见 pc_bsphp_hb_classify）：
 *   PC_HB_FATAL     → 写日志后 ExitProcess(0)，结束整个进程；
 *   PC_HB_TRANSIENT → 重握手并重试一次，仍失败只记日志，继续下一周期；
 *   PC_HB_OK        → 静默。
 * 返回 PC_OK / PC_ERR_SERVER（CreateThread 失败）。 */
int32_t pc_bsphp_heartbeat_start(void);
int32_t pc_bsphp_heartbeat_stop(void);
/* 线程是否仍在跑（1=在跑，0=已停 / 从未启动）。 */
int32_t pc_bsphp_heartbeat_is_running(void);

/* 从响应 JSON 里取一个字符串字段（"key":"value" 形式），有界拷贝。
 * 找到返回 1，否则 0（out 会被置空串）。 */
int pc_bsphp_json_field(const char* json, const char* key, char* out,
                        size_t cap);

/* 从响应 JSON 里取一个整数字段，兼容 "code":1011 与 "code":"1011" 两种写法
 * （不同版本后台返回类型不一致）。取到返回 1，否则 0。 */
int pc_bsphp_json_int(const char* json, const char* key, int* out);

/* 状态码判定：按响应 JSON 里的 code 查表。
 *   返回  1 = 该状态码表示成功
 *   返回  0 = 该状态码表示失败
 *   返回 -1 = 表里没有这个码（调用方自行兜底） */
int pc_bsphp_code_ok(int code);

/* 状态码对应的中文原文；表里没有返回 NULL。 */
const char* pc_bsphp_code_text(int code);

/* 「会话是否已死」—— 等价于 pc_bsphp_hb_classify 判为 PC_HB_FATAL。
 *
 * 保留这个符号只为不破坏既有调用方（pc_auth.c 的会话自愈用它判断
 * 「这条会话还能不能用」）。语义已随三级分类收窄：
 *   返回 1 = 冻结 / 到期 / 被顶号 / 账号级超时 / **在线数超限** —— 会话彻底不可用；
 *   返回 0 = 其余一切。注意 1049 / 5027 **不再算死**：
 *            它们是本地会话问题或瞬时失败，重新握手即可恢复。 */
int pc_bsphp_session_dead(int code);

#endif /* PC_BSPHP_H */
