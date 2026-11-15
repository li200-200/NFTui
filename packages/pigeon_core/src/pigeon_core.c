/* ---------------------------------------------------------------------------
 * C 核心的导出层。
 *
 * 这一层只做「ABI 边界」该做的事：拦空指针、保证不崩、把调用转给对应模块。
 * 业务规则一律不写在这里 —— 那些在 pc_auth.c / pc_task.c。
 *
 * 所有对外符号都定义在本文件，好处是审计契约是否被遵守时只需要看一处。
 * ------------------------------------------------------------------------- */

#include "pigeon_core.h"

#include "pc_auth.h"
#include "pc_bsphp.h"
#include "pc_cred.h"
#include "pc_http.h"
#include "pc_log.h"

#include <stddef.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#endif

/* ===========================================================================
 * ABI 自检
 * ========================================================================= */

/* 编译期断言：结构体布局一旦与 Dart 镜像不一致，这里先编译失败，
 * 不必等到运行时读出错位数据。
 *
 * 数值来自 lib/src/types.dart 的镜像（sizeOf<T>() 的口径：C 结构体尺寸）。
 * 改动任何 lens 宏都必须同时改 Dart 侧与这里的期望值。
 *
 * 【本工程只移植了验证页（登录 / 注册 / 充值）依赖的那部分 C 模块】
 * 原 snap 工程还有 task / shide / engine / notify / sound 五套业务，
 * 它们的结构体（pc_task_row、pc_shide_*、pc_engine_*）在这里不存在，
 * 对应的 ABI 断言与 probe 项已一并删除。若以后移植那些模块，必须把
 * 断言与 probe 顺序按原工程恢复 —— Dart 侧是按顺序比对的。 */
#define PC_ABI_MSG_CHECK(cond, tag) \
  typedef char pc_abi_check_##tag[(cond) ? 1 : -1]

PC_ABI_MSG_CHECK(sizeof(pc_form_result) == 24, form_result);
PC_ABI_MSG_CHECK(sizeof(pc_auth_result) == 4 + 24 + 256 + 512, auth_result);

/* 字段偏移同样钉死：只有尺寸对、偏移错，一样会读错字段。 */
PC_ABI_MSG_CHECK(offsetof(pc_auth_result, form) == 4, off_auth_form);
PC_ABI_MSG_CHECK(offsetof(pc_auth_result, message) == 28, off_auth_msg);
PC_ABI_MSG_CHECK(offsetof(pc_auth_result, data) == 284, off_auth_data);

int32_t pc_abi_probe(int32_t* out, int32_t cap) {
  int32_t n = 0;
  if (out == NULL || cap <= 0) return PC_ERR_INVALID_ARG;
  /* 顺序固定；Dart 侧按同一顺序比对（见 pigeon_core.dart 的 _abiExpect）。 */
#define PC_ABI_PUT(v) \
  do { \
    if (n >= cap) return PC_ERR_BUFFER_SMALL; \
    out[n++] = (int32_t)(v); \
  } while (0)
  PC_ABI_PUT(sizeof(pc_form_result));
  PC_ABI_PUT(sizeof(pc_auth_result));
  /* 字段偏移不在这里输出：它们在上面由编译期断言钉死（offsetof 的静态断言
   * 一旦不符就直接编译失败），运行时没必要再走一遍 —— Dart 侧也没有
   * offsetOf<T>() 可用于比对（Struct 只有 sizeOf）。 */
#undef PC_ABI_PUT
  return n;
}

/* ===========================================================================
 * 全局握手锁
 *
 * BSPHP 的 bootstrap（internet.in + BSphpSeSsL.in）会被四个地方触发：
 * 登录、注册、充值、公告（经 pc_auth.c 的 ensure），以及心跳自愈
 * （pc_bsphp.c 的 hb_loop）。早先只有 pc_auth.c 自己有一把静态锁，
 * 心跳那条路径完全不持锁 —— 两轮握手可以并发，各建一条匿名会话互相覆盖，
 * 并让 pc_auth_bsphp_reset() 的「清零 + 作废会话」被反向覆盖，自愈失效。
 *
 * 现在锁只有一把，放在导出层，谁要握手都得先拿它。
 * ========================================================================= */

#if defined(_WIN32)
static SRWLOCK g_boot_lock = SRWLOCK_INIT;

void pc_boot_lock_acquire(void) { AcquireSRWLockExclusive(&g_boot_lock); }
void pc_boot_lock_release(void) { ReleaseSRWLockExclusive(&g_boot_lock); }
#else
/* 非 Windows 的联网路径是空实现，锁退化为空操作。 */
void pc_boot_lock_acquire(void) {}
void pc_boot_lock_release(void) {}
#endif

/* ===========================================================================
 * 认证
 * ========================================================================= */

/* ---- 第一段：表单校验（同步，不碰网络） ---- */

int32_t pc_auth_validate_login(const char* user, const char* pwd,
                               pc_form_result* out) {
  if (user == NULL || pwd == NULL || out == NULL) {
    return PC_ERR_INVALID_ARG;
  }
  return pc_auth_validate_login_impl(user, pwd, out);
}

int32_t pc_auth_validate_register(const char* user, const char* pwd,
                                  const char* pwd2, const char* card,
                                  pc_form_result* out) {
  if (user == NULL || pwd == NULL || pwd2 == NULL || card == NULL ||
      out == NULL) {
    return PC_ERR_INVALID_ARG;
  }
  return pc_auth_validate_register_impl(user, pwd, pwd2, card, out);
}

int32_t pc_auth_validate_recharge(const char* user, const char* confirm,
                                  const char* card, pc_form_result* out) {
  if (user == NULL || confirm == NULL || card == NULL || out == NULL) {
    return PC_ERR_INVALID_ARG;
  }
  return pc_auth_validate_recharge_impl(user, confirm, card, out);
}

/* ---- 第二段：提交（同步阻塞，发真实请求） ---- */

int32_t pc_auth_login(const char* user, const char* pwd,
                      pc_auth_result* out) {
  if (user == NULL || pwd == NULL || out == NULL) {
    return PC_ERR_INVALID_ARG;
  }
  return pc_auth_login_impl(user, pwd, out);
}

int32_t pc_auth_register(const char* user, const char* pwd, const char* pwd2,
                         const char* card, pc_auth_result* out) {
  if (user == NULL || pwd == NULL || pwd2 == NULL || card == NULL ||
      out == NULL) {
    return PC_ERR_INVALID_ARG;
  }
  return pc_auth_register_impl(user, pwd, pwd2, card, out);
}

int32_t pc_auth_recharge(const char* user, const char* confirm,
                          const char* card, pc_auth_result* out) {
  if (user == NULL || confirm == NULL || card == NULL || out == NULL) {
    return PC_ERR_INVALID_ARG;
  }
  return pc_auth_recharge_impl(user, confirm, card, out);
}

int32_t pc_auth_notice(void) { return pc_auth_notice_impl(); }

/* ---- 登录心跳（后台线程，见头文件里的显式例外说明） ---- */

int32_t pc_heartbeat_start(void) { return pc_bsphp_heartbeat_start(); }

int32_t pc_heartbeat_stop(void) { return pc_bsphp_heartbeat_stop(); }

int32_t pc_heartbeat_is_running(int32_t* out_running) {
  if (out_running == NULL) {
    return PC_ERR_INVALID_ARG;
  }
  *out_running = pc_bsphp_heartbeat_is_running();
  return PC_OK;
}

/* ---- 退出收尾 ---- */

/* 全进程唯一的一次性收尾闩。
 *
 * 两条线程会同时走到收尾：UI 线程（窗口关闭）与心跳线程（授权失效）。
 * 早先两处各调一次 pc_log_shutdown()，而那个函数**非幂等**（两次 CloseHandle
 * 同一句柄是未定义行为，可能关掉别的线程刚复用的同值句柄）。这里用
 * InterlockedCompareExchange 抢一次：抢不到的直接原地挂起，让抢到的那条
 * 线程把进程结束掉 —— 不会再有两个线程同时拆资源。 */
static volatile LONG g_shutdown_latch = 0;

/* 抢到闩的那条线程「资源已经拆完」的标记（见下面「后来者」的等待）。 */
static volatile LONG g_shutdown_done = 0;

/* 后来者最多等这么久。取值必须覆盖抢到闩那条线程的最坏耗时：
 * 心跳 stop（立即）+ 音效 stop（≤500ms）+ 任务 stop（立即）+ 掐网络（立即）
 * + 日志收尾（刷新线程等待 ≤1s）≈ 1.6 秒。早先写死 Sleep(2000) 与这条最坏
 * 路径几乎打平 —— 一旦音效正在播 7.8 秒的音轨（旧实现要等 3 秒），后来者
 * 就会在 2 秒时 TerminateProcess，把抢到闩那线程的 pc_log_shutdown / fclose
 * 全部跳过，最后几条日志与账户/订单文件被截断。
 * 现在放宽到 4000ms，并且**分片轮询** g_shutdown_done：拆完了就立刻退出，
 * 不会白等满 4 秒。 */
#define PC_SHUTDOWN_WAIT_MS 4000
#define PC_SHUTDOWN_SLICE_MS 100

int32_t pc_core_shutdown(int64_t now_ms) {
  if (InterlockedCompareExchange(&g_shutdown_latch, 1, 0) != 0) {
    /* 已有另一条线程在收尾。给它一点时间把日志 / 文件落完，然后自己硬退。
     *
     * 【绝不能无限 Sleep】早先这里是 `for (;;) Sleep(1000)`：抢到闩的那条线程
     * 若卡在 pc_log_shutdown 的 WaitForSingleObject（1s）或 pc_sound_shutdown
     * 的等待（3s）里，后来者就会**永久挂住** —— 用户点关闭后窗口显示「未响应」，
     * 只能去任务管理器强杀，正是「关窗假死」的直接成因。
     *
     * 现在改成有界等待 + 自己结束进程：抢到闩的线程本来就会 TerminateProcess，
     * 这段等待只是保证它的日志先落盘；之后无论它在哪一步，都由这里兜底退出。
     *
     * 【分片轮询而不是一次 Sleep 到底】抢到闩的线程拆完资源后会把
     * g_shutdown_done 置 1，此时立刻退出即可，不必白等满 PC_SHUTDOWN_WAIT_MS。
     * 只有它真的卡住（例如卡在一个不可中断的系统调用里）才走满超时。 */
#if defined(_WIN32)
    {
      ULONGLONG deadline = GetTickCount64() + PC_SHUTDOWN_WAIT_MS;
      while (GetTickCount64() < deadline) {
        if (InterlockedCompareExchange(&g_shutdown_done, 0, 0) != 0) break;
        Sleep(PC_SHUTDOWN_SLICE_MS);
      }
    }
    TerminateProcess(GetCurrentProcess(), 0);
#endif
    return PC_OK;
  }

  /* 1) 停心跳：协作式，置标志即返回，避免退出瞬间还在发网络请求。 */
  pc_bsphp_heartbeat_stop();
  /* 2) 掐断所有在飞的 WinHTTP 请求。
   *
   * 上一步只是「置停止标志」，工作线程可能还卡在 WinHttpReceiveResponse /
   * WinHttpReadData 里（最长 connect 10s + read 15s）。不掐断就只能等它们自然
   * 超时，或者直接 TerminateProcess —— 后者会让这些线程在任意指令处消失，
   * 栈上缓冲与堆块没人收尾，退出还会卡满 25s。
   * 关掉它们的 request 句柄后，挂起的调用立刻以取消错误返回，线程沿正常路径
   * 退栈、解锁、free。见 pc_http.c 里 pc_http_abort_all 的说明。 */
  pc_http_abort_all();
  /* 3) 停日志刷新线程 + 释放日志控制台（conhost.exe 随之退出）。 */
  pc_log_shutdown();
  /* 【资源已拆完，通知后来者立刻退出】
   *
   * 这一步必须在 pc_log_shutdown 之后：日志收尾本身要等刷新线程（≤1s）并
   * fclose，后来者若在这之前就 TerminateProcess，那几条日志和文件就会丢。
   * 置位之后，后来者不再等满 PC_SHUTDOWN_WAIT_MS，而是立刻结束进程。 */
  InterlockedExchange(&g_shutdown_done, 1);
  /* 4) 硬终止：线程、句柄、窗口由内核一次性回收。见头文件说明。
   *
   * 用 TerminateProcess 而不是 ExitProcess：
   *   ExitProcess 会等待所有线程走到各自的 DllMain(PROCESS_DETACH) 才返回，
   *   而引擎线程此刻可能正卡在最长 25s 的网络调用里 —— 于是「点关闭」之后
   *   进程会僵住一段时间（甚至因为 Flutter 引擎的 detach 需要 UI 线程参与
   *   而互相等待）。终止前该停的都停了，剩下交给内核回收更确定。 */
#if defined(_WIN32)
  TerminateProcess(GetCurrentProcess(), 0);
#endif
  return PC_OK; /* 不可达（Windows 上 TerminateProcess 不返回） */
}

/* ===========================================================================
 * 记住密码
 * ========================================================================= */

int32_t pc_cred_default_path(char* out, int32_t cap) {
  if (out == NULL || cap <= 0) {
    return PC_ERR_INVALID_ARG;
  }
  return pc_cred_impl_default_path(out, cap);
}

int32_t pc_cred_save(const char* path, const char* user, const char* pwd,
                     int32_t remember, int32_t auto_login) {
  if (path == NULL || user == NULL || pwd == NULL) {
    return PC_ERR_INVALID_ARG;
  }
  return pc_cred_impl_save(path, user, pwd, remember, auto_login);
}

int32_t pc_cred_load(const char* path, char* out_user, int32_t user_cap,
                     char* out_pwd, int32_t pwd_cap, int32_t* out_remember,
                     int32_t* out_auto_login) {
  if (path == NULL) {
    return PC_ERR_INVALID_ARG;
  }
  return pc_cred_impl_load(path, out_user, user_cap, out_pwd, pwd_cap,
                           out_remember, out_auto_login);
}
