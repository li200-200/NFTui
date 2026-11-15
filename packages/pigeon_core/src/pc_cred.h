/* ---------------------------------------------------------------------------
 * 记住密码：把「是否记住 / 是否自动登录 / 用户名 / 密码」持久化到本地文件。
 *
 * 设计取舍：
 *   - 密码做一层 XOR 混淆，**不是真加密**。「记住密码」本身就是一个可逆的
 *     约定（下次启动要把密码原样填回输入框），所以这里只求「别让密码明文
 *     直接躺在一个 .txt 里被人一眼看到」，不承诺对抗有意的逆向。
 *   - 文件不存在 / 内容损坏，一律当成「没有记住」处理，load 仍返回成功 ——
 *     调用方不需要区分「没记住过」和「文件读坏了」，行为上都是空表单。
 *
 * 存储位置由 pc_cred_default_path 给出，应用把它当成一个不透明字符串传回来。
 * ------------------------------------------------------------------------- */

#ifndef PC_CRED_H
#define PC_CRED_H

#include <stdint.h>

#include "pigeon_core.h"

/* 默认存储路径：%LOCALAPPDATA%\pigeon_assist_cred.dat
   （LOCALAPPDATA 取不到时退到当前目录的 pigeon_assist_cred.dat）。
   写进 out，返回 PC_OK；cap 不够返回 PC_ERR_BUFFER_SMALL。 */
int32_t pc_cred_impl_default_path(char* out, int32_t cap);

/* 保存。remember 为 0 时写一份空记录（等价于清空已记住的内容）。
   auto_login 只在 remember 为 1 时才有意义，但这里不替调用方做这个约束。 */
int32_t pc_cred_impl_save(const char* path, const char* user, const char* pwd,
                          int32_t remember, int32_t auto_login);

/* 读取。任一出参可为 NULL 表示不关心。
   文件不存在或损坏 → remember=0、user/pwd 为空、返回 PC_OK。 */
int32_t pc_cred_impl_load(const char* path, char* out_user, int32_t user_cap,
                          char* out_pwd, int32_t pwd_cap, int32_t* out_remember,
                          int32_t* out_auto_login);

#endif /* PC_CRED_H */
