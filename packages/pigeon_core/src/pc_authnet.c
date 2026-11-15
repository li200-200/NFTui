/* ---------------------------------------------------------------------------
 * pc_authnet.h 的实现 —— 仅剩「本机机器码」。
 *
 * 早先这里还有整套 1wxyun（文心云）网络验证客户端：RC4 + Base64 参数编码、
 * 5 条官方线路重试、JSON 信封解析、公告拉取、软标识 / 密钥配置。
 * 业务已迁到 BSPHP（见 pc_bsphp.c），那条链路全部失去调用方，已随本次清理
 * 整体删除（连其专属的 pc_crypt.c / pc_errtab.c 一并移除）。
 *
 * 保留项：机器码。BSPHP 的登录 / 注册仍要用它作为 key 与 maxoror 提交。
 * ------------------------------------------------------------------------- */

#include "pc_authnet.h"

#include <string.h>

#if defined(_WIN32)
/* 机器码要读注册表 / 卷序列号。 */
#include <windows.h>
/* RegOpenKeyEx 这几个在 advapi32 里，不是 kernel32。不显式挂上会出现
   「无法解析的外部符号 __imp_RegOpenKeyExA」—— 报的是符号名而不是库名，
   第一次遇到容易往「函数名写错了」的方向查。 */
#pragma comment(lib, "advapi32.lib")
#endif

/* 有界字符串拷贝（机器码兜底串用）。 */
static void pc_copy_str(char* dst, size_t cap, const char* src) {
  size_t n;

  if (dst == NULL || cap == 0) {
    return;
  }
  if (src == NULL) {
    src = "";
  }
  n = strlen(src);
  if (n >= cap) n = cap - 1;
  memcpy(dst, src, n);
  dst[n] = '\0';
}

size_t pc_authnet_machine_code(char* out, size_t cap) {
  if (out == NULL || cap == 0) {
    return 0;
  }
  out[0] = '\0';

#if defined(_WIN32)
  /* 优先读注册表里的 MachineGuid：装系统时生成，重装前不变，
     正好是「这台机器」的稳定标识。 */
  {
    HKEY key = NULL;
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
                      "SOFTWARE\\Microsoft\\Cryptography", 0, KEY_READ,
                      &key) == ERROR_SUCCESS) {
      char buf[64];
      DWORD size = sizeof(buf);
      DWORD type = 0;
      LONG rc = RegQueryValueExA(key, "MachineGuid", NULL, &type, (LPBYTE)buf,
                                 &size);
      RegCloseKey(key);
      if (rc == ERROR_SUCCESS && (type == REG_SZ || type == REG_EXPAND_SZ)) {
        size_t p = 0;
        size_t i;
        buf[sizeof(buf) - 1] = '\0';
        /* 去掉连字符，只留字母数字 —— 官方要求机器码是不超过 32 位
           的字母数字，36 位的 GUID 直接传会被判「机器码填写错误」。 */
        for (i = 0; buf[i] != '\0' && p + 1 < cap; i++) {
          char c = buf[i];
          if ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
              (c >= 'A' && c <= 'F')) {
            out[p++] = c;
          }
        }
        out[p] = '\0';
        if (p >= 8) {
          return p;
        }
      }
    }
  }
  /* 兜底：系统盘卷序列号（8 位十六进制），比时间戳稳定得多。 */
  {
    DWORD serial = 0;
    if (GetVolumeInformationA("C:\\", NULL, 0, &serial, NULL, NULL, NULL, 0)) {
      static const char kHex[] = "0123456789ABCDEF";
      size_t p = 0;
      int shift;
      for (shift = 28; shift >= 0 && p + 1 < cap; shift -= 4) {
        out[p++] = kHex[(serial >> shift) & 0x0Fu];
      }
      out[p] = '\0';
      return p;
    }
  }
#endif

  /* 两条路都不通时的兜底。常量而不是时间戳：机器码每次变会让服务端
     判成「在别的机器登陆」，宁可全部机器共用一个也先保证能登进去。 */
  pc_copy_str(out, cap, "00000000");
  return strlen(out);
}