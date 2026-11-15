/* ---------------------------------------------------------------------------
 * 运行日志（不可关闭的控制台窗口）。
 *
 * pc_log_init 分配一个控制台窗口用于打印运行日志，并禁用其关闭按钮；
 * pc_log 输出一行带时间戳的日志。非 Windows 平台为空实现，保证可编译。
 * ------------------------------------------------------------------------- */

#ifndef PC_LOG_H
#define PC_LOG_H

#include "pigeon_core.h"

/* 初始化日志控制台（不可关闭）并重定向 stdout。可重复调用。 */
PC_API void pc_log_init(void);

/* 安装崩溃处理器：进程崩溃/闪退时把异常信息写进 crash.log。可重复调用。 */
PC_API void pc_crash_install(void);

/* 输出一行日志（自动带 [HH:mm:ss] 时间前缀并换行）。
 * 日志是行缓冲的（攒够 4KB 或距上次输出超过 200ms 才真的写一次，降低高频刷日志
 * 时写控制台的开销）；需要立刻看到某条日志时再调 [pc_log_flush]。
 *
 * 下面的 format 注解让编译器/静态分析校验「格式串与参数个数是否一致」：
 * 曾经因为格式串少写一个 %s，参数被错位消费，把手机号当成等级打了出来。
 * MSVC 不认识 __attribute__，这条只在 clang / IDE 静态分析侧生效。 */
#if defined(__GNUC__) || defined(__clang__)
__attribute__((format(printf, 1, 2)))
#endif
void pc_log(const char* fmt, ...);

/* 输出一条现成的文本（不加格式）。给 Dart 侧写日志用 —— FFI 没法传可变参数，
 * 所以单独开一个入口。内部就是 pc_log("%s", text) 的等价实现。 */
PC_API void pc_log_text(const char* text);

/* 把行缓冲里还没写出的日志立刻写到控制台。
 * 抢单成功 / 失败这种「用户要立刻看到结果」的日志后面会调它；未初始化日志时是
 * 安全的空操作。 */
void pc_log_flush(void);

/* 把一行日志（自动带 [YYYY-MM-DD HH:mm:ss] 时间前缀并换行）追加写进
 * exe 目录下的 pigeon.log。
 *
 * 与 [pc_log] 分开的原因：pc_log 写的是控制台，而「心跳失败 → 结束进程」这种
 * 场景下控制台会随进程一起销毁，那条日志根本来不及被看到 —— 落盘才是事后可查的。
 * 每次调用单独 fopen/fclose：只在进程即将结束 / 关键失败时调用，不在热路径上，
 * 换来「不依赖后台线程 / atexit」的确定性 —— 函数返回时内容一定已经在文件里。
 * 「进程即将结束」这类场景（心跳终止）用它，而不是 pc_log。 */
#if defined(__GNUC__) || defined(__clang__)
__attribute__((format(printf, 1, 2)))
#endif
void pc_log_file(const char* fmt, ...);

/* 进程即将结束时的收尾：刷出剩余日志、停掉日志刷新线程、FreeConsole 释放日志
 * 控制台、关闭崩溃日志句柄。可重复调用（幂等）。
 *
 * 释放控制台是必须的：AllocConsole 建出的控制台由 conhost.exe 托管，若不显式
 * 释放，某些退出路径（尤其是后台线程里硬终止）会在任务管理器里残留一个
 * conhost.exe。正常退出由 atexit 自动调用；pc_core_shutdown 走的是硬终止、
 * 不执行 atexit，需在退出前手动调一次。 */
void pc_log_shutdown(void);

/* 把可能是 GBK（系统 ANSI 代码页）的文本统一转成 UTF-8 用于展示：
   若本身就是合法 UTF-8 则原样返回，否则按 ANSI/GBK -> UTF-8 转换。
   用于修复服务器下发 GBK 公告在 CP_UTF8 控制台下乱码的问题。 */
PC_API void pc_to_utf8(const char* in, char* out, size_t out_cap);

#endif /* PC_LOG_H */
