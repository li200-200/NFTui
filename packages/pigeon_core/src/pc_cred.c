/* ---------------------------------------------------------------------------
 * pc_cred.h 的实现。
 *
 * 文件格式（小端、定长头 + 两个变长字段）：
 *   [0..7]   magic "PGCRED1"（8 字节，含结尾 NUL）
 *   [8]      flags：bit0 = remember，bit1 = auto_login
 *   [9..12]  uint32 user_len
 *   [13..]   user 的 UTF-8 字节
 *   ...      uint32 pwd_len
 *   ...      pwd 的 UTF-8 字节（每个字节 XOR 0x5A）
 *
 * 读的时候先校验 magic 与长度上限，任何一个对不上就当成「没有记住」——
 * 一个损坏的文件不该让应用崩溃，也不该填进半个密码。
 * ------------------------------------------------------------------------- */

#include "pc_cred.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h> /* MoveFileExA：原子替换 */
#include <dpapi.h>   /* CryptProtectData / CryptUnprotectData */
#include <wincrypt.h>
#pragma comment(lib, "crypt32.lib")
#endif

/* 文件格式版本 2：密码字段改为 DPAPI 加密。
 *
 * 版本 1（PGCRED1）用的是逐字节 XOR 0x5A —— 那不是加密，本机任意进程
 * 打开文件就能还原明文密码。版本 2 用 CryptProtectData：
 *   · 密钥由系统按「当前用户 + 当前机器」派生，别的用户 / 别的机器解不开；
 *   · 加密结果与文件一起存放，无需额外密钥管理。
 * 仍然不是「防逆向」级别的保护（同用户的进程可以调同一个 API 解密），
 * 但它把「记事本打开就看见密码」变成了「必须主动调用系统 API」，
 * 与文件本身的 ACL 叠加之后是合理的桌面工具强度。
 *
 * 兼容性：读取时按 magic 判断版本，PGCRED1 的旧文件仍能读（XOR 还原），
 * 下次保存时自动升级成 PGCRED2。 */
#define PC_CRED_MAGIC "PGCRED2"
#define PC_CRED_MAGIC_LEN 8 /* 7 个可见字符 + 1 个 NUL */
#define PC_CRED_MAGIC_V1 "PGCRED1"
#define PC_CRED_XOR 0x5A /* 只用于读取旧格式 */

/* DPAPI 输出的最大长度（256 字节明文 + 头部开销，留足余量）。 */
#define PC_CRED_BLOB_MAX 1024

/* 抹掉内存里的敏感数据（密码明文）。
 *
 * SecureZeroMemory 是 Windows 宏；非 Windows 编译时用 volatile 写实现等价语义
 * —— 关键是「编译器不能把这次写入优化掉」，memset 会被 DCE 掉。 */
static void pc_cred_wipe(void* p, size_t n) {
#if defined(_WIN32)
  SecureZeroMemory(p, n);
#else
  volatile unsigned char* v = (volatile unsigned char*)p;
  while (n-- > 0) {
    *v++ = 0;
  }
#endif
}

/* 账号与密码在本地文件里的长度上限。正常账号 16 位、密码 16 位，
   256 字节留了足够余量；超出直接拒绝写入，避免一个异常输入把文件撑爆。 */
#define PC_CRED_FIELD_MAX 256

int32_t pc_cred_impl_default_path(char* out, int32_t cap) {
  const char* appdata;
  const char kFile[] = "\\pigeon_assist_cred.dat";

  if (out == NULL || cap <= 0) {
    return PC_ERR_INVALID_ARG;
  }
  out[0] = '\0';

  /* LOCALAPPDATA 优先；取不到时退到 %TEMP%，最后才退到当前目录。
   *
   * 退到 "." 的问题：进程的工作目录可能正是安装目录（Program Files），
   * 普通用户没有写权限，记住密码会静默失效；更糟的是「当前目录」是可控的，
   * 在某些启动方式下会把凭据文件写到别的地方。
   * TEMP 一定是当前用户可写的私有目录，语义与 LOCALAPPDATA 一致。 */
  appdata = getenv("LOCALAPPDATA");
  if (appdata == NULL || appdata[0] == '\0') {
    appdata = getenv("TEMP");
  }
  if (appdata == NULL || appdata[0] == '\0') {
    appdata = getenv("USERPROFILE");
  }
  if (appdata == NULL || appdata[0] == '\0') {
    return PC_ERR_IO;
  }

  /* 用有界拼接：早先 strcpy + strcat 依赖上面那次长度判断，任何一处改动
   * （比如把 kFile 改成带子目录的路径）都会立刻溢出。 */
  {
    size_t n = strlen(appdata);
    size_t k = sizeof(kFile) - 1; /* 不含结尾 NUL */
    if (n + k + 1 > (size_t)cap) {
      return PC_ERR_BUFFER_SMALL;
    }
    memcpy(out, appdata, n);
    memcpy(out + n, kFile, k + 1); /* 连结尾 NUL 一起拷 */
  }
  return PC_OK;
}

/* 写一个 uint32 到文件，失败返回 0。 */
static int pc_write_u32(FILE* f, uint32_t v) {
  return fwrite(&v, sizeof(v), 1, f) == 1;
}

/* 读一个 uint32，失败返回 0。 */
static int pc_read_u32(FILE* f, uint32_t* v) {
  return fread(v, sizeof(*v), 1, f) == 1;
}

/* 用 DPAPI 加密一段数据（绑定当前用户 + 当前机器）。成功返回 1，
 * 输出写入 out（长度写进 *out_len）。失败返回 0。 */
static int pc_cred_protect(const unsigned char* in, size_t in_len,
                           unsigned char* out, size_t out_cap,
                           size_t* out_len) {
#if defined(_WIN32)
  DATA_BLOB data_in;
  DATA_BLOB data_out;
  BOOL ok;

  if (in == NULL || out == NULL || out_len == NULL) return 0;
  data_in.cbData = (DWORD)in_len;
  data_in.pbData = (BYTE*)in;
  data_out.cbData = 0;
  data_out.pbData = NULL;
  /* 用户态作用域：同一个 Windows 账号才能解密，别的用户/机器都不行。 */
  ok = CryptProtectData(&data_in, L"pigeon_cred", NULL, NULL, NULL,
                        CRYPTPROTECT_UI_FORBIDDEN, &data_out);
  if (!ok) return 0;
  if (data_out.cbData > out_cap) {
    pc_cred_wipe(data_out.pbData, data_out.cbData);
    LocalFree(data_out.pbData);
    return 0;
  }
  memcpy(out, data_out.pbData, data_out.cbData);
  *out_len = data_out.cbData;
  pc_cred_wipe(data_out.pbData, data_out.cbData);
  LocalFree(data_out.pbData);
  return 1;
#else
  (void)in; (void)in_len; (void)out; (void)out_cap; (void)out_len;
  return 0; /* 非 Windows：没有 DPAPI，保存时退回旧格式 */
#endif
}

/* 用 DPAPI 解密。成功返回 1，明文写入 out（长度写进 *out_len）。 */
static int pc_cred_unprotect(const unsigned char* in, size_t in_len,
                             unsigned char* out, size_t out_cap,
                             size_t* out_len) {
#if defined(_WIN32)
  DATA_BLOB data_in;
  DATA_BLOB data_out;
  BOOL ok;

  if (in == NULL || out == NULL || out_len == NULL) return 0;
  data_in.cbData = (DWORD)in_len;
  data_in.pbData = (BYTE*)in;
  data_out.cbData = 0;
  data_out.pbData = NULL;
  ok = CryptUnprotectData(&data_in, NULL, NULL, NULL, NULL,
                          CRYPTPROTECT_UI_FORBIDDEN, &data_out);
  if (!ok) return 0;
  if (data_out.cbData > out_cap) {
    pc_cred_wipe(data_out.pbData, data_out.cbData);
    LocalFree(data_out.pbData);
    return 0;
  }
  memcpy(out, data_out.pbData, data_out.cbData);
  *out_len = data_out.cbData;
  pc_cred_wipe(data_out.pbData, data_out.cbData);
  LocalFree(data_out.pbData);
  return 1;
#else
  (void)in; (void)in_len; (void)out; (void)out_cap; (void)out_len;
  return 0;
#endif
}

/* 临时文件路径：path 后面接 ".tmp"。返回 0 成功，-1 表示 path 太长。 */
#define PC_CRED_PATH_MAX 1024
static int pc_cred_tmp_path(const char* path, char* out, size_t cap) {
  size_t n = strlen(path);
  if (n + 5 > cap) return -1;
  memcpy(out, path, n);
  memcpy(out + n, ".tmp", 5); /* 含结尾 NUL */
  return 0;
}

int32_t pc_cred_impl_save(const char* path, const char* user, const char* pwd,
                          int32_t remember, int32_t auto_login) {
  FILE* f;
  uint32_t ulen;
  uint32_t plen;
  uint32_t i;
  unsigned char obf[PC_CRED_FIELD_MAX];
  unsigned char blob[PC_CRED_BLOB_MAX];
  unsigned char flags;
  size_t blob_len = 0;
  int use_dpapi = 0;
  char tmp[PC_CRED_PATH_MAX];
  int failed = 0;

  if (path == NULL || user == NULL || pwd == NULL) {
    return PC_ERR_INVALID_ARG;
  }

  ulen = (uint32_t)strlen(user);
  plen = (uint32_t)strlen(pwd);
  /* obf[] 是 PC_CRED_FIELD_MAX 字节，后面按 plen 逐字节写进去 —— 所以上限
   * 必须是「严格小于」，早先允许 == 时最后一个字节越界一字节。
   * 另外 strlen 的 size_t 到 uint32_t 的强转在超长输入下会截断，
   * 这里先用 size_t 比较再转。 */
  if (strlen(user) >= PC_CRED_FIELD_MAX || strlen(pwd) >= PC_CRED_FIELD_MAX) {
    return PC_ERR_INVALID_ARG;
  }
  if (pc_cred_tmp_path(path, tmp, sizeof(tmp)) != 0) {
    return PC_ERR_BUFFER_SMALL;
  }

  /* 先写临时文件、再原子替换。
   *
   * 为什么：早先直接 fopen(path,"wb") 就地覆盖 —— 若写入过程中进程被杀
   * （用户关窗口时正好在保存、或崩溃），磁盘上留下的就是「半截文件」：
   * magic 对、ulen 对、密码只写了一半。下次启动读到的密码是残缺的，
   * 用户看到「密码错误」却怎么改都不对，只能手动去删 dat 文件。
   * 临时文件 + MoveFileEx 保证任何时刻 path 指向的要么是旧完整文件、
   * 要么是新完整文件，不存在中间态。 */
  f = fopen(tmp, "wb");
  if (f == NULL) {
    return PC_ERR_IO;
  }

  flags = (unsigned char)((remember ? 1 : 0) | (auto_login ? 2 : 0));

  /* 密码优先走 DPAPI。DPAPI 不可用（非 Windows / 极端环境）时才退回
   * 旧的 XOR 格式 —— 此时写的是 PGCRED1，读取端按 magic 区分。 */
  use_dpapi = (plen > 0) &&
              pc_cred_protect((const unsigned char*)pwd, plen, blob,
                              sizeof(blob), &blob_len);

  if (fwrite(use_dpapi ? PC_CRED_MAGIC : PC_CRED_MAGIC_V1, 1,
             PC_CRED_MAGIC_LEN, f) != PC_CRED_MAGIC_LEN ||
      fwrite(&flags, 1, 1, f) != 1 || !pc_write_u32(f, ulen) ||
      (ulen > 0 && fwrite(user, 1, ulen, f) != ulen)) {
    failed = 1;
  }

  /* 密码段：DPAPI 密文长度可变，所以先写长度再写内容；
   * 退回旧格式时长度仍是 plen，内容按 XOR 混淆。 */
  if (!failed) {
    uint32_t stored_len = use_dpapi ? (uint32_t)blob_len : plen;
    if (!pc_write_u32(f, stored_len)) {
      failed = 1;
    } else if (use_dpapi) {
      if (stored_len > 0 && fwrite(blob, 1, stored_len, f) != stored_len) {
        failed = 1;
      }
    } else if (plen > 0) {
      for (i = 0; i < plen; i++) {
        obf[i] = (unsigned char)pwd[i] ^ PC_CRED_XOR;
      }
      if (fwrite(obf, 1, plen, f) != plen) {
        failed = 1;
      }
    }
  }
  /* 栈上的明文副本用完即抹：这段代码之后 pwd 仍在调用方手里，
   * 但 obf / blob 没有必要继续留在栈上等下一次复用它的人。 */
  pc_cred_wipe(obf, sizeof(obf));
  pc_cred_wipe(blob, sizeof(blob));

  if (fclose(f) != 0) {
    failed = 1;
  }
  if (failed) {
    /* 半截临时文件不能留在磁盘上（下次启动虽然读的是 path，但留着会误导排查）。 */
    remove(tmp);
    return PC_ERR_IO;
  }

  /* 原子替换：Windows 上 MoveFileEx 带 REPLACE_EXISTING 等价于 rename(2)，
     写坏一次也不会让旧文件消失。 */
#if defined(_WIN32)
  if (!MoveFileExA(tmp, path, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    remove(tmp);
    return PC_ERR_IO;
  }
#else
  remove(path); /* POSIX rename 会覆盖，但有些实现要求目标不存在 */
  if (rename(tmp, path) != 0) {
    remove(tmp);
    return PC_ERR_IO;
  }
#endif
  return PC_OK;
}

int32_t pc_cred_impl_load(const char* path, char* out_user, int32_t user_cap,
                          char* out_pwd, int32_t pwd_cap, int32_t* out_remember,
                          int32_t* out_auto_login) {
  FILE* f;
  char magic[PC_CRED_MAGIC_LEN];
  unsigned char flags;
  uint32_t ulen;
  uint32_t plen;
  unsigned char raw[PC_CRED_BLOB_MAX];
  unsigned char plain[PC_CRED_FIELD_MAX];
  int is_v2 = 0;
  uint32_t i;

  if (path == NULL) {
    return PC_ERR_INVALID_ARG;
  }

  /* 先给出「没有记住」的缺省值，任何一步失败都能直接返回。 */
  if (out_user != NULL && user_cap > 0) {
    out_user[0] = '\0';
  }
  if (out_pwd != NULL && pwd_cap > 0) {
    out_pwd[0] = '\0';
  }
  if (out_remember != NULL) {
    *out_remember = 0;
  }
  if (out_auto_login != NULL) {
    *out_auto_login = 0;
  }

  f = fopen(path, "rb");
  if (f == NULL) {
    return PC_OK; /* 没记住过 */
  }

  if (fread(magic, 1, PC_CRED_MAGIC_LEN, f) != PC_CRED_MAGIC_LEN ||
      (memcmp(magic, PC_CRED_MAGIC, PC_CRED_MAGIC_LEN) != 0 &&
       memcmp(magic, PC_CRED_MAGIC_V1, PC_CRED_MAGIC_LEN) != 0) ||
      fread(&flags, 1, 1, f) != 1 || !pc_read_u32(f, &ulen) ||
      ulen > PC_CRED_FIELD_MAX) {
    fclose(f);
    return PC_OK; /* 损坏，当没记住 */
  }
  /* 按 magic 记住格式版本：PGCRED2 的密码段是 DPAPI 密文，
   * PGCRED1（历史文件）是 XOR 混淆。 */
  is_v2 = (memcmp(magic, PC_CRED_MAGIC, PC_CRED_MAGIC_LEN) == 0) ? 1 : 0;

  if (ulen > 0 &&
      fread(raw, 1, ulen, f) != ulen) {
    fclose(f);
    return PC_OK;
  }
  /* user_cap 可能是 0 或负数：早先 (uint32_t)user_cap - 1 在 cap==0 时
   * 下溢成 0xFFFFFFFF，n 就变成 ulen —— 越过调用方的缓冲。
   * 现在先判 cap 有效再算上限。 */
  if (ulen > 0 && out_user != NULL && user_cap > 0) {
    uint32_t cap = (uint32_t)user_cap;
    uint32_t n = (ulen < cap - 1) ? ulen : (cap - 1);
    memcpy(out_user, raw, n);
    out_user[n] = '\0';
  }

  /* v2 的密码段是 DPAPI 密文（比明文长），上限按 blob 容量判；
   * v1 的密码段是明文长度，上限按字段容量判。 */
  if (!pc_read_u32(f, &plen) ||
      plen > (is_v2 ? (uint32_t)PC_CRED_BLOB_MAX
                    : (uint32_t)PC_CRED_FIELD_MAX)) {
    fclose(f);
    return PC_OK;
  }
  if (plen > 0 && fread(raw, 1, plen, f) != plen) {
    fclose(f);
    return PC_OK;
  }
  if (plen > 0 && out_pwd != NULL && pwd_cap > 0) {
    const unsigned char* src = raw;
    size_t src_len = plen;
    size_t plain_len = 0;
    uint32_t cap = (uint32_t)pwd_cap;

    if (is_v2) {
      /* DPAPI 解不开（换了机器 / 换了用户 / 文件被篡改）→ 当成「没有记住」，
       * 不要把密文当密码填进输入框。 */
      if (!pc_cred_unprotect(raw, plen, plain, sizeof(plain), &plain_len)) {
        pc_cred_wipe(raw, sizeof(raw));
        fclose(f);
        return PC_OK;
      }
      src = plain;
      src_len = plain_len;
    }
    {
      uint32_t n = (src_len < (size_t)(cap - 1)) ? (uint32_t)src_len
                                                 : (cap - 1);
      for (i = 0; i < n; i++) {
        out_pwd[i] = (char)(is_v2 ? src[i] : (src[i] ^ PC_CRED_XOR));
      }
      out_pwd[n] = '\0';
    }
    pc_cred_wipe(plain, sizeof(plain));
  }
  pc_cred_wipe(raw, sizeof(raw));

  if (out_remember != NULL) {
    *out_remember = (flags & 1) ? 1 : 0;
  }
  if (out_auto_login != NULL) {
    *out_auto_login = (flags & 2) ? 1 : 0;
  }

  fclose(f);
  return PC_OK;
}
