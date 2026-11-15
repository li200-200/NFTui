/* ---------------------------------------------------------------------------
 * 认证模块（登录 / 注册 / 充值）的内部接口。
 *
 * 规则来自服务端的实际要求：
 * 用户名 6-16 位且只能是字母数字、密码至少 6 位。
 * 本地先按宽松规则放过、再由服务端回一句拒绝，对用户是白等一次往返。
 *
 * 这一层的约定：
 *   - 只管业务规则，不做入参校验 —— 空指针由导出层 pigeon_core.c 拦掉；
 *   - 一定会把 *out 完整写一遍，调用方不会读到未初始化的槽位；
 *   - 不认识界面文案：某字段该显示哪句话由 Dart 侧按「哪个槽位 + 哪个码」
 *     决定（本地校验失败要求「只红框抖动、不出文字」，文案本属表现层）。
 *     只有服务端结果这类「非说不可」的文字才由网络层给出。
 *
 * 每个业务接口都有一个 validate_ 版本：只做表单校验、不碰网络。
 * 两者共用同一份校验实现（见 pc_auth.c 里的 pc_form_* ），规则不会漂移。
 * ------------------------------------------------------------------------- */

#ifndef PC_AUTH_H
#define PC_AUTH_H

#include <stdint.h>

#include "pigeon_core.h"

/* 校验阈值。 */
#define PC_USER_MIN_LEN 6
#define PC_USER_MAX_LEN 16
#define PC_PWD_MIN_LEN 6

/* 卡密下限。注意这不是服务端的规则。
   这里只做「明显无效的输入不往服务器发」这一层宽松拦截：8 位的卡密照样会
   发出去，让服务端告诉我们准确规则，用户看到的是官方提示语，
   而不是我们猜出来的文案。 */
#define PC_CARD_MIN_LEN 8

/* 本地长度上限，**不是服务端规则**，纯粹为了防止超长输入在传输层被静默
   截断（请求参数缓冲装不下时 snprintf 会悄悄截掉尾巴，用户只会看到
   「密码错误」，排查时看不出原因）。真实账号 16 位、密码 ≤16、卡密 16 位，
   64 位留了足够余量；超过这个长度本地直接判 TOO_LONG。 */
#define PC_PWD_MAX_LEN 64
#define PC_CARD_MAX_LEN 64

/* ---- 第一段：只校验表单，绝不发请求 ---- */

int32_t pc_auth_validate_login_impl(const char* user, const char* pwd,
                                    pc_form_result* out);

int32_t pc_auth_validate_register_impl(const char* user, const char* pwd,
                                       const char* pwd2, const char* card,
                                       pc_form_result* out);

int32_t pc_auth_validate_recharge_impl(const char* user, const char* confirm,
                                       const char* card, pc_form_result* out);

/* ---- 第二段：校验通过后发真实请求 ---- */

int32_t pc_auth_login_impl(const char* user, const char* pwd,
                           pc_auth_result* out);

int32_t pc_auth_register_impl(const char* user, const char* pwd,
                              const char* pwd2, const char* card,
                              pc_auth_result* out);

int32_t pc_auth_recharge_impl(const char* user, const char* confirm,
                              const char* card, pc_auth_result* out);

/* 系统公告（api_type "1"）。获取公告并逐条输出到运行日志。 */
int32_t pc_auth_notice_impl(void);

#endif /* PC_AUTH_H */
