/* ---------------------------------------------------------------------------
 * 机器码（本机稳定标识）。
 *
 * 这里原本是 1wxyun（文心云）网络验证客户端，业务迁到 BSPHP 后整条联网验证
 * 链路已删除（见 pc_authnet.c 顶部说明）。仅保留机器码 —— BSPHP 的登录 /
 * 注册仍需要它作为 key 与 maxoror 提交。
 * ------------------------------------------------------------------------- */

#ifndef PC_AUTHNET_H
#define PC_AUTHNET_H

#include <stddef.h>
#include <stdint.h>

#include "pigeon_core.h"

/* 本机机器码。服务端用它做设备绑定，必须**稳定**，否则每次登录都被判成
   「在别的机器登陆」。
   取值顺序：注册表 MachineGuid → 系统盘卷序列号 → 固定串兜底。
   返回写入的字符数（不含结尾 NUL）。 */
size_t pc_authnet_machine_code(char* out, size_t cap);

#endif /* PC_AUTHNET_H */