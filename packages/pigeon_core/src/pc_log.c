/* ---------------------------------------------------------------------------
 * 运行日志实现。
 *
 * Windows：AllocConsole 分配控制台，freopen 把 stdout/stderr 指到 CONOUT$，
 * 再用 GetSystemMenu + DeleteMenu 删除系统菜单的「关闭」项，使窗口不可关闭。
 * ------------------------------------------------------------------------- */

#ifndef PIGEON_CORE_BUILD
#define PIGEON_CORE_BUILD 1
#endif

#include "pc_log.h"

#if defined(_WIN32)

#include <windows.h>
/* 仅 pc_crash_install（安装期、进程健康）用 MODULEENTRY32 预捕获模块表；
   崩溃处理器本身不再调任何 Toolhelp API。 */
#include <tlhelp32.h>

/* GetSystemMenu / DeleteMenu 在 user32.lib，CLibrary 不会默认链接。
 *
 * 刻意**不**链接 dbghelp：崩溃处理器里早先用 SymInitialize / StackWalk64 回溯
 * 调用栈，但那两个 API 要拿加载器锁，而崩溃时刻别的线程可能正持着它 ——
 * 处理器自己会死锁，进程既不落盘也退不出去。详见 pc_crash_handler 的说明。 */
#pragma comment(lib, "user32.lib")

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* 0=未初始化 / 已关闭，1=可写。这个标志会被几十个工作线程无锁读，退出时又要
 * 由 UI 线程清 0，所以必须是 LONG 并全程走 Interlocked*：
 * 退出流程一旦把它清 0，还在跑的引擎线程立刻静默，不会再往已经 FreeConsole 的
 * stdout 里写（见 pc_log_shutdown 的说明）。 */
static volatile LONG g_log_ready = 0;

/* 崩溃处理器重入闩（见 pc_crash_handler）：0 = 还没人处理，1 = 已有实例在处理。
 * 用 LONG 而不是 bool，是为了能在崩溃现场用 Interlocked* 原子抢占 —— 那里
 * 不能拿任何锁。 */
static volatile LONG g_crashing = 0;

/* ---------------------------------------------------------------------------
 * 行缓冲：每行都 fputs + fflush 的代价很高 —— 一次 flush 就要真的写一次
 * conhost（控制台还要滚动重绘），抢单引擎有几十个工作线程时会在这里排队。
 * 所以把整行先攒进共享缓冲，满足「够 4KB」或「距上次 flush 超过 200ms」才写
 * 一次。200ms 超时刷新由一个常驻后台线程（pc_log_flush_thread_proc）兜底执行，
 * 因此「最后一条日志」也会在 ~200ms 内自动显示，调用方一般不必再显式 pc_log_flush()；
 * 只有需要「写完立刻就看到」（比如公告）时才额外显式 flush。日志内容与格式完全不变，
 * 只是输出的时机批量化了。
 * ------------------------------------------------------------------------- */
#define PC_LOG_BUF_CAP 8192
#define PC_LOG_FLUSH_BYTES 4096
#define PC_LOG_FLUSH_MS 200

static char g_log_buf[PC_LOG_BUF_CAP];
static size_t g_log_len;
static ULONGLONG g_log_last_flush;
static CRITICAL_SECTION g_log_lock;

/* 输出串行锁（**必须最先拿**，锁序固定 io → log）。
 *
 * 为什么要把「攒缓冲」和「真正写出去」拆成两把锁：早先 log_flush_locked 是在
 * g_log_lock 里直接 fwrite + fflush 到控制台/文件。控制台写入要经过 conhost，
 * 单次毫秒级；抢单活跃期每秒几十条日志，于是全部工作线程在 g_log_lock 上排队，
 * 引擎整体被日志拖慢 —— 这是「拖慢抢单速度」最直接的一条。
 *
 * 现在：
 *   · g_log_lock 只护内存（append / 换出缓冲），持锁时间是微秒级；
 *   · g_log_io_lock 只被「要写盘的那一条线程」持有，fwrite 在它里面完成；
 *   · 换出缓冲用 g_log_swap，复制在 g_log_lock 内完成，因此换出与写入不会
 *     互相踩（写出去的永远是已经脱离共享缓冲的那一份）。
 * 两个锁的获取顺序固定为 io → log，所有路径一致，不存在死锁。 */
static char g_log_swap[PC_LOG_BUF_CAP];
static CRITICAL_SECTION g_log_io_lock;
/* g_log_lock 是否已经 InitializeCriticalSection 过。
 *
 * 退出路径（pc_log_shutdown / log_free_console）可能在「从未初始化日志」时
 * 被调用（例如登录页就授权失效、或用户在日志初始化前关窗）。对未初始化的
 * CRITICAL_SECTION 调 Enter/Leave 是未定义行为，所以进出锁之前都要看这个标志。
 * 只在 InitOnce 里写 1，之后只读。 */
static volatile LONG g_log_lock_ready = 0;

/* 日志输出目标（只在初始化时确定一次，之后只读）。
 *
 * 正常情况下就是 stdout（指向 AllocConsole 出来的 CONOUT$）。但如果控制台建不出来
 * （比如宿主把 stdio 重定向到别处、或被启动器以无控制台方式拉起、或 freopen 失败），
 * 早先的做法是**整体关掉日志**：g_log_ready 保持 0，所有 pc_log 变成空操作。
 * 后果是现场一旦出现这种环境，用户报「闪退」时日志窗口里什么都没有、连一条
 * 启动记录都看不到，只能靠猜。
 *
 * 现在改成降级到文件：控制台不行就写 exe 目录下的 pigeon.log，日志功能照常
 * 工作，只是没有窗口。正常路径（控制台可用）行为完全不变。 */
static FILE* g_log_out = NULL;

/* 控制台控制事件处理（定义在下面「控制台控制事件处理」一节）。 */
static BOOL WINAPI pc_log_ctrl_handler(DWORD type);

/* 尝试附着控制台；成功返回 1。失败时不改动任何全局状态。 */
static int pc_log_console_attach(void) {
  FILE* f = NULL;
  HWND hwnd;
  if (!AllocConsole()) return 0;
  if (freopen_s(&f, "CONOUT$", "w", stdout) != 0 || f == NULL) {
    FreeConsole();
    return 0;
  }
  f = NULL;
  if (freopen_s(&f, "CONOUT$", "w", stderr) != 0 || f == NULL) {
    FreeConsole();
    return 0;
  }

  /* 控制台按 UTF-8 解释输出，避免中文乱码。 */
  SetConsoleOutputCP(CP_UTF8);

  /* 关闭「快速编辑」模式（ENABLE_QUICK_EDIT_MODE）。
   *
   * Windows 控制台默认开启它：用户用鼠标在日志窗口里拖选文字（想复制一条抢单
   * 记录）时，conhost 会进入选择状态并**阻塞所有写入**，直到按 Esc 或回车。
   * 而 pc_log 要把缓冲写进控制台 —— 于是第一个写入的线程卡在 fwrite 里、写锁
   * 不放，其余最多 128 个工作线程 + 调度线程 + 旁路线程 + 心跳线程全部排队，
   * 整个引擎停摆（表现为「卡死 / 抢单变慢 / 点了没反应」）。
   *
   * 置位顺序有讲究：必须先打开 ENABLE_EXTENDED_FLAGS，否则单独清
   * ENABLE_QUICK_EDIT_MODE 不会生效（这是 SetConsoleMode 的老规矩）。
   * 取不到句柄 / 设置失败都不影响日志功能，只是保留旧行为。 */
  {
    HANDLE hout = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD mode = 0;
    if (hout != NULL && hout != INVALID_HANDLE_VALUE &&
        GetConsoleMode(hout, &mode)) {
      mode |= ENABLE_EXTENDED_FLAGS;
      mode &= ~ENABLE_QUICK_EDIT_MODE;
      SetConsoleMode(hout, mode);
    }
  }

  /* 禁用关闭：删掉系统菜单里的「关闭」项（右上角 X 变灰）。 */
  hwnd = GetConsoleWindow();
  if (hwnd != NULL) {
    HMENU menu = GetSystemMenu(hwnd, FALSE);
    if (menu != NULL) {
      DeleteMenu(menu, SC_CLOSE, MF_BYCOMMAND);
    }
  }

  /* 用宽字符版本设置标题，避免 ANSI 版按 GBK 解释 UTF-8 字节导致乱码。 */
  SetConsoleTitleW(L"鸽鸽软件助手 - 运行日志");

  /* 注册控制台控制事件处理（见 pc_log_ctrl_handler 的说明）。
     注册失败不影响日志功能，只是少了 Ctrl-C 保护。 */
  SetConsoleCtrlHandler(pc_log_ctrl_handler, TRUE);
  return 1;
}

/* 降级：把日志写进 exe 目录下的 pigeon.log（追加）。失败返回 NULL（彻底静默）。 */
static FILE* pc_log_open_file(void) {
  char dir[MAX_PATH];
  char path[MAX_PATH];
  FILE* f;
  dir[0] = '\0';
  GetModuleFileNameA(NULL, dir, sizeof(dir));
  {
    char* slash = strrchr(dir, '\\');
    if (slash != NULL) slash[1] = '\0';
  }
  snprintf(path, sizeof(path), "%spigeon.log", dir);
  f = fopen(path, "ab");
  return f;
}

/* pc_log_init 的一次性初始化（见函数处的说明）。 */
static INIT_ONCE g_log_init_once = INIT_ONCE_STATIC_INIT;

/* 后台刷新线程的句柄 / 停止事件 / 运行标志（见 pc_log_flush_thread_proc）。
 * 停止事件用于进程退出时立刻唤醒线程，不必干等一个完整周期。 */
static HANDLE g_log_flush_thread;
static HANDLE g_log_stop_event;
static volatile int g_log_flush_run = 0;

/* 把共享行缓冲里的内容**换出**到 g_log_swap，返回本次要写的字节数（0 = 没内容）。
 *
 * 调用方必须持有 g_log_lock。这里只做 memcpy + 清零，不碰任何 I/O，
 * 所以持锁时间是微秒级 —— 这正是「不拖慢抢单」的关键。 */
static size_t log_take_locked(void) {
  size_t n;
  if (g_log_len == 0) return 0;
  if (g_log_out == NULL) {
    /* 无输出去处（已收尾 / 降级失败）：丢弃而不是崩。 */
    g_log_len = 0;
    return 0;
  }
  n = g_log_len;
  memcpy(g_log_swap, g_log_buf, n);
  g_log_len = 0;
  g_log_last_flush = GetTickCount64();
  return n;
}

/* 把 g_log_swap 里前 n 字节真正写到输出目标。
 *
 * 调用方必须持有 g_log_io_lock，**不能**持有 g_log_lock（锁序 io → log）。
 * 这里的 fwrite 可能被 conhost 阻塞（滚动重绘、甚至用户按了窗口暂停），
 * 但它只堵住这一条写线程，不再堵住任何 pc_log 调用方。 */
static void log_write_taken(size_t n) {
  FILE* out;
  if (n == 0) return;
  /* 目标可能在收尾时被换掉：读 g_log_out 要进 g_log_lock（锁序 io → log）。 */
  EnterCriticalSection(&g_log_lock);
  out = g_log_out;
  LeaveCriticalSection(&g_log_lock);
  if (out == NULL) return; /* 已释放：这份内容无处可写，丢弃 */
  fwrite(g_log_swap, 1, n, out);
  fflush(out);
}

/* 兼容旧调用点：把缓冲刷出去。内部按「先 io 锁、再 log 锁」的顺序拿锁。 */
static void log_flush_all(void) {
  size_t n;
  EnterCriticalSection(&g_log_io_lock);
  EnterCriticalSection(&g_log_lock);
  n = log_take_locked();
  LeaveCriticalSection(&g_log_lock);
  log_write_taken(n);
  LeaveCriticalSection(&g_log_io_lock);
}

/* 崩溃时用的最小信息集：全部在安装期（进程健康时）预捕获，崩溃处理器只读。
 *
 * 为什么不在这里现场枚举模块：CreateToolhelp32Snapshot / SymInitialize 都要
 * 拿加载器锁，崩溃时刻别的线程很可能正持着它（比如正好在 CreateThread /
 * LoadLibrary / 首次 malloc 里）—— 处理器会卡死在那里，日志写不出来、进程也
 * 退不掉，正是「闪退后进程清不掉」的典型成因。
 * 预捕获之后，处理器只做 GetLocalTime + GetCurrentThreadId + WriteFile，
 * 这三个都不依赖加载器锁，也不依赖 CRT 的 FILE* 锁。 */
#define PC_CRASH_MODULE_MAX 96
typedef struct {
  ULONG_PTR base;
  ULONG_PTR end;
  char name[MAX_PATH];
} pc_crash_module;

static pc_crash_module g_crash_modules[PC_CRASH_MODULE_MAX];
static int g_crash_module_count = 0;
static HANDLE g_crash_file = INVALID_HANDLE_VALUE; /* 预先打开，崩溃时直接用 */

/* 打印某个地址所属的模块名与相对偏移（RVA）。只用预捕获的表，不调 API。 */
static void pc_crash_module_note(char* out, size_t cap, ULONG_PTR addr) {
  int i;
  for (i = 0; i < g_crash_module_count; i++) {
    if (addr >= g_crash_modules[i].base && addr < g_crash_modules[i].end) {
      /* 模块名可能带路径，只取文件名。 */
      const char* full = g_crash_modules[i].name;
      const char* base = full;
      const char* p;
      for (p = full; *p != '\0'; p++) {
        if (*p == '\\' || *p == '/') base = p + 1;
      }
      snprintf(out, cap, "  <%s+0x%llX>", base,
               (unsigned long long)(addr - g_crash_modules[i].base));
      return;
    }
  }
  out[0] = '\0';
}

/* 异常代码 → 可读名称。 */
static const char* pc_exception_name(DWORD code) {
  switch (code) {
    case EXCEPTION_ACCESS_VIOLATION: return "访问冲突(ACCESS_VIOLATION)";
    case EXCEPTION_ARRAY_BOUNDS_EXCEEDED: return "数组越界(ARRAY_BOUNDS)";
    case EXCEPTION_BREAKPOINT: return "断点(BREAKPOINT)";
    case EXCEPTION_DATATYPE_MISALIGNMENT: return "数据对齐错误(MISALIGNMENT)";
    case EXCEPTION_FLT_DIVIDE_BY_ZERO: return "浮点除零(FLT_DIV_BY_ZERO)";
    case EXCEPTION_FLT_OVERFLOW: return "浮点溢出(FLT_OVERFLOW)";
    case EXCEPTION_INT_DIVIDE_BY_ZERO: return "整数除零(INT_DIV_BY_ZERO)";
    case EXCEPTION_INT_OVERFLOW: return "整数溢出(INT_OVERFLOW)";
    case EXCEPTION_STACK_OVERFLOW: return "栈溢出(STACK_OVERFLOW)";
    case EXCEPTION_ILLEGAL_INSTRUCTION: return "非法指令(ILLEGAL_INSTRUCTION)";
    case EXCEPTION_IN_PAGE_ERROR: return "页面错误(IN_PAGE_ERROR)";
    default: return "未知异常";
  }
}

/* 写一行崩溃日志。snprintf 返回的是「本应写入的长度」，被截断时会大于缓冲；
 * 这里统一钳到 cap-1，避免把尾部 NUL 也一起 WriteFile 出去（越界读 1 字节，
 * 且在出异常的时刻没有任何收益）。 */
static void pc_crash_write_line(const char* text, int len, size_t cap) {
  DWORD written = 0;
  size_t n = len > 0 ? (size_t)len : 0;
  if (n >= cap) n = cap - 1;
  if (n > 0) WriteFile(g_crash_file, text, (DWORD)n, &written, NULL);
}

/* 崩溃处理器：把异常信息追加写进 exe 目录下的 crash.log，然后终止进程。
 *
 * 这个函数运行在**出异常的那个线程**上，此刻堆锁 / 加载器锁 / CRT 流锁都可能
 * 正被别的线程持有。因此这里刻意只用「不依赖这些锁」的最小 API 集合：
 *   GetLocalTime / GetCurrentThreadId / snprintf(局部缓冲) / WriteFile
 * 绝不调用：malloc、fopen/fprintf（CRT 流锁 + 堆锁）、CreateToolhelp32Snapshot、
 * SymInitialize / StackWalk64（加载器锁）。那些一旦撞上持锁线程就会死锁 ——
 * 表现是「崩溃了但日志没写、进程也退不掉」，正是要避免的现象。
 * 模块信息在 pc_crash_install 时预捕获，这里只查表。 */
/* 崩溃处理器自己的栈需求必须**尽量小**：栈溢出触发的崩溃里，处理器要用的栈
 * 正是刚刚被压爆的那一段（保护页还没恢复）。早先这里是 line[1024] +
 * note[320] + frames[32×8=256] ≈ 1.6KB，在 1MB 栈的引擎线程上溢出时很容易
 * 二次压爆 —— 表现就是「闪退，crash.log 里一条都没有」。
 * 现在压到 line[640] + note[192] + frames[24×8=192] ≈ 1KB，并且所有写出行都
 * 走 pc_crash_write_line 的截断保护（超长只截断，不会越界）。 */
static LONG WINAPI pc_crash_handler(EXCEPTION_POINTERS* ep) {
  SYSTEMTIME st;
  char line[640];
  char note[192];
  DWORD code = 0;
  ULONG_PTR addr = 0;
  int n;

  /* 重入闩：崩溃处理器自己也可能崩。
   *
   * 典型场景：栈溢出时处理器被调起，而它自己又要用 ~1KB 栈（line/note/帧数组），
   * 于是**在处理崩溃的过程中再崩一次**；栈保护页还没恢复，嵌套异常又会进来，
   * 一层层叠下去 —— 表现就是「闪退，日志里什么都没有，甚至看不到第一条记录」。
   * 这里用一次 InterlockedCompareExchange 抢占：抢到的那个实例负责写日志，
   * 后面进来的（包括递归的）直接跳过写盘、立刻 TerminateProcess，保证进程一定
   * 能退掉。 */
  if (InterlockedCompareExchange(&g_crashing, 1, 0) != 0) {
    /* 重入（崩溃处理器自己又崩了）：直接结束进程。
     * 这里刻意**不再**引用 code —— 它此刻还没赋值，早先那版把未初始化的
     * 值当退出码传出去，事件查看器里永远是 0，排查时看不出真实原因。 */
    InterlockedExchange(&g_log_ready, 0);
    TerminateProcess(GetCurrentProcess(), 1);
    return EXCEPTION_EXECUTE_HANDLER;
  }

  GetLocalTime(&st);
  if (ep != NULL && ep->ExceptionRecord != NULL) {
    code = ep->ExceptionRecord->ExceptionCode;
    addr = (ULONG_PTR)ep->ExceptionRecord->ExceptionAddress;
  }

  /* 只有安装时成功打开了文件才会走到这里。 */
  if (g_crash_file != INVALID_HANDLE_VALUE) {
    pc_crash_module_note(note, sizeof(note), addr);
    n = snprintf(line, sizeof(line),
                 "[%04d-%02d-%02d %02d:%02d:%02d] 线程=0x%lX 程序崩溃：%s "
                 "(0x%08X) 地址 0x%p%s\r\n",
                 st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
                 (unsigned long)GetCurrentThreadId(), pc_exception_name(code),
                 (unsigned int)code, (void*)addr, note);
    if (n > 0) {
      pc_crash_write_line(line, n, sizeof(line));
    }

    /* 寄存器（x64）——异常上下文里的值，不需要任何 API。 */
#if defined(_M_X64) || defined(_M_AMD64)
    if (ep != NULL && ep->ContextRecord != NULL) {
      CONTEXT* c = ep->ContextRecord;
      pc_crash_module_note(note, sizeof(note), (ULONG_PTR)c->Rip);
      n = snprintf(line, sizeof(line),
                   "  RIP=0x%p RSP=0x%p RBP=0x%p%s\r\n"
                   "  RAX=0x%p RBX=0x%p RCX=0x%p RDX=0x%p\r\n",
                   (void*)c->Rip, (void*)c->Rsp, (void*)c->Rbp, note,
                   (void*)c->Rax, (void*)c->Rbx, (void*)c->Rcx, (void*)c->Rdx);
      if (n > 0) {
        pc_crash_write_line(line, n, sizeof(line));
      }
    }
#endif

    /* 调用栈：只用 CaptureStackBackTrace（读栈，不拿任何全局锁），
       逐帧查预捕获的模块表给出模块+偏移。够定位到具体函数，
       需要更精确的解析可以事后用 .map / PDB 离线做。 */
    {
      void* frames[24];
      USHORT count = CaptureStackBackTrace(0, 24, frames, NULL);
      USHORT i;
      const char hdr[] = "  调用栈（最近在前）：\r\n";
      pc_crash_write_line(hdr, (int)(sizeof(hdr) - 1), sizeof(hdr));
      for (i = 0; i < count; i++) {
        pc_crash_module_note(note, sizeof(note), (ULONG_PTR)frames[i]);
        n = snprintf(line, sizeof(line), "    #%u 0x%p%s\r\n", (unsigned int)i,
                     frames[i], note);
        if (n > 0) {
          pc_crash_write_line(line, n, sizeof(line));
        }
      }
    }
  }

  /* 写完立即终止进程，不再交回系统默认处理。
   *
   * 早先是 return EXCEPTION_EXECUTE_HANDLER 让 Windows 弹「程序已停止工作」的
   * WER 对话框 —— 只要没人点掉它，进程就一直挂着，它带出来的 conhost.exe 也跟着
   * 残留，任务管理器里越积越多（正是「闪退后进程清不掉」的主因）。日志此刻已经
   * 落盘，没有理由再停在这里等人点按钮。
   *
   * 先 FreeConsole 释放日志控制台（conhost 立即退出），再 TerminateProcess 硬杀
   * 自己：线程、句柄、窗口由内核一次性回收，退出干净且确定。 */
  /* 同样先断日志开关：崩溃后其它线程还活着，它们若再 pc_log 就会写已经释放的
     控制台（fwrite 到失效句柄本身不崩，但没必要冒这个险）。 */
  InterlockedExchange(&g_log_ready, 0);
  FreeConsole();
  TerminateProcess(GetCurrentProcess(), (UINT)code);
  return EXCEPTION_EXECUTE_HANDLER; /* 兜底：TerminateProcess 正常情况下不返回 */
}

PC_API void pc_crash_install(void) {
  char dir[MAX_PATH];
  char path[MAX_PATH];
  HANDLE snap;
  MODULEENTRY32 me;

  /* 安装期做两件重活（此时进程健康，加锁无风险）：
   *   1) 打开 crash.log 并一直持有句柄 —— 崩溃时不必再走 fopen（CRT 锁）；
   *   2) 枚举一次已加载模块，存下基址/大小/名字 —— 崩溃时不必再调
   *      CreateToolhelp32Snapshot（加载器锁）。 */
  if (g_crash_file == INVALID_HANDLE_VALUE) {
    dir[0] = '\0';
    GetModuleFileNameA(NULL, dir, sizeof(dir));
    {
      char* slash = strrchr(dir, '\\');
      if (slash != NULL) slash[1] = '\0';
    }
    snprintf(path, sizeof(path), "%scrash.log", dir);
    g_crash_file = CreateFileA(path, FILE_APPEND_DATA,
                               FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                               OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
  }

  if (g_crash_module_count == 0) {
    snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32,
                                    GetCurrentProcessId());
    if (snap != INVALID_HANDLE_VALUE) {
      me.dwSize = sizeof(me);
      if (Module32First(snap, &me)) {
        do {
          if (g_crash_module_count < PC_CRASH_MODULE_MAX) {
            pc_crash_module* m = &g_crash_modules[g_crash_module_count++];
            m->base = (ULONG_PTR)me.modBaseAddr;
            m->end = (ULONG_PTR)me.modBaseAddr + me.modBaseSize;
            /* 名字有界拷贝，避免模块路径超过 MAX_PATH 时溢出。 */
            strncpy(m->name, me.szExePath, sizeof(m->name) - 1);
            m->name[sizeof(m->name) - 1] = '\0';
          }
        } while (Module32Next(snap, &me));
      }
      CloseHandle(snap);
    }
  }

  SetUnhandledExceptionFilter(pc_crash_handler);
}

/* 后台刷新线程：pc_log 内的 200ms 超时刷新只在「下一条日志到来」时才会被评估，
 * 若写完后不再有日志输出（例如停在登录界面等待），缓冲会一直滞留。这个常驻线程
 * 周期（PC_LOG_FLUSH_MS）冲刷缓冲，使任何「最后一条日志」都最多延迟约 200ms 显示，
 * 不必每个调用方都记着显式 pc_log_flush()。线程只在日志已初始化后运行，而 pc_log_flush
 * 对未初始化 / 空缓冲都是安全的空操作。 */
static DWORD WINAPI pc_log_flush_thread_proc(LPVOID unused) {
  (void)unused;
  while (g_log_flush_run) {
    /* 用「可唤醒的等待」代替 Sleep：退出时能立刻收线程，不必干等一个周期。 */
    if (WaitForSingleObject(g_log_stop_event, PC_LOG_FLUSH_MS) == WAIT_OBJECT_0) {
      break;
    }
    if (!g_log_flush_run) break;
    pc_log_flush();
  }
  return 0;
}

/* 进程退出时收掉刷新线程。
 *
 * 为什么必须有这一步：进程退出时 CRT 会关闭 stdout，而其它线程要等到 ExitProcess
 * 才被终止——中间这段时间里，本线程若再去 fwrite 一个已经关闭的 FILE*，就是
 * 「退出瞬间闪退」的典型来源。atexit 回调在 CRT 关闭流**之前**执行，所以在这里
 * 让线程停下，就能保证它不会再碰到已关闭的 stdout。 */
static void log_free_console(void);

static void pc_log_stop_flush_thread(void) {
  /* 【幂等】pc_log_shutdown 会被两条线程同时调用：UI 线程（窗口关闭 →
   * pc_core_shutdown）与心跳线程（授权失效 → pc_core_shutdown）。虽然
   * pc_core_shutdown 现在有一次性闩，atexit 仍然可能与之并发。
   *
   * 早先这里没有任何保护：同一 HANDLE 被 CloseHandle 两次是未定义行为，
   * 完全可能关掉别的线程刚复用的同值句柄。现在用一个原子闩保证整段只跑一次。 */
  static volatile LONG stopped = 0;
  if (InterlockedExchange(&stopped, 1) != 0) {
    log_free_console();
    return;
  }

  /* 提到函数作用域：下面的「事件句柄要不要关」也要看这次等待的结果。
   *
   * 初值给 WAIT_OBJECT_0 是**有依据的**：只有「刷新线程从未建出来」时才会
   * 保留初值（g_log_flush_thread == NULL），那种情况下根本不存在等待者，
   * 关事件句柄本来就是安全的。线程存在时一定会被下面那次等待覆盖。 */
  DWORD w = WAIT_OBJECT_0;

  if (g_log_flush_thread != NULL) {
    g_log_flush_run = 0;
    if (g_log_stop_event != NULL) SetEvent(g_log_stop_event);
    /* 等线程真正退出（最多 1s）。等不到就放弃：宁可少刷一条日志也不能卡住退出。 */
    w = WaitForSingleObject(g_log_flush_thread, 1000);
    if (w == WAIT_OBJECT_0) {
      /* 只有确认已退出才关句柄。早先无条件 CloseHandle：线程还活着时句柄被关，
       * 之后它仍在跑，而进程退出阶段 CRT 会先关流 —— 该线程下一次 fwrite 就是
       * 写一个已失效的 FILE*，正是「退出瞬间闪退」的来源。等不到就**不关**，
       * 让内核在进程结束时统一回收（泄漏一个句柄，换来退出路径确定）。 */
      CloseHandle(g_log_flush_thread);
    }
    g_log_flush_thread = NULL;
  }
  if (g_log_stop_event != NULL) {
    /* 【只在线程确认退出后才关事件句柄】
     *
     * 早先这里无条件 CloseHandle(g_log_stop_event)。而上面那次等待可能是超时
     * （线程正卡在 pc_log_flush 的控制台 I/O 里），它下一轮就会重新
     * WaitForSingleObject(g_log_stop_event, 200) —— 关闭一个**正被等待**的句柄
     * 是未定义行为：轻则 WAIT_FAILED 空转，重则碰已回收的内核对象。
     *
     * 与上面「等不到就不关线程句柄」同一个取舍：确认线程已退出（w ==
     * WAIT_OBJECT_0）才关事件；超时就留给内核在进程结束时统一回收。 */
    if (w == WAIT_OBJECT_0) {
      CloseHandle(g_log_stop_event);
    }
    g_log_stop_event = NULL;
  }
  log_free_console();
}

/* 释放控制台。
 *
 * AllocConsole 建出的控制台由 conhost.exe 托管，它只会在这个控制台**不再被任何
 * 进程附着**时才结束。进程正常退出时系统会回收，但「进程被 ExitProcess 从后台
 * 线程强制结束」这种路径下不一定 —— 结果就是任务管理器里残留一个 conhost.exe。
 * 显式 FreeConsole 立即断开附着，conhost 随之退出。两条退出路径都走这里：
 * 窗口关闭（CRT 退出 → atexit）与 pc_core_shutdown 硬终止（TerminateProcess 前手调）。 */
static void log_free_console(void) {
  static volatile LONG freed = 0;
  FILE* to_close = NULL;

  if (InterlockedExchange(&freed, 1) != 0) return;
  /* 先断掉日志开关再拆控制台：此刻可能还有引擎线程在 pc_log 里，
     清 0 之后新进入的调用只会走到空返回。 */
  InterlockedExchange(&g_log_ready, 0);

  /* 【必须持 g_log_lock 再换掉 g_log_out】
   *
   * 早先这里是裸写 g_log_out = NULL + fclose(f)，与 pc_log() 之间没有任何
   * 同步。pc_log 的流程是「检查 g_log_ready → EnterCriticalSection →
   * fwrite(g_log_out)」，检查与 fwrite 之间没有和这里的任何互斥：
   *   · 线程 A 已通过 g_log_ready 检查、正在临界区里；
   *   · 本函数清 0 并 fclose 掉同一个 FILE*；
   *   · 线程 A 继续 fwrite 一个已关闭的 FILE* → 写已释放对象。
   * 「开关清 0 后新调用直接空返回」只对新进入者成立，救不了已在临界区里的线程。
   *
   * 现在在锁内完成「摘掉 g_log_out」，锁外的 fwrite 拿到的是 NULL 就不会写。 */
  /* 【锁序 io → log，与 pc_log 一致】
   *
   * g_log_io_lock 必须先拿：可能有线程正持有它做 fwrite。等它释放之后再摘
   * g_log_out，才能保证「摘掉」发生在所有在途写入之后 —— 否则那条线程手里的
   * FILE* 会变成刚被 fclose 的对象（写已释放内存）。 */
  if (InterlockedCompareExchange(&g_log_lock_ready, 0, 0) != 0) {
    EnterCriticalSection(&g_log_io_lock);
    EnterCriticalSection(&g_log_lock);
  }
  if (g_log_out != NULL && g_log_out != stdout) {
    /* 文件降级模式：关掉自己打开的文件（stdout 由 CRT 收尾，不在这里碰）。 */
    to_close = g_log_out;
  }
  g_log_out = NULL;
  g_log_len = 0; /* 缓冲里的内容无处可去，直接丢弃，避免写进已释放的流 */
  if (InterlockedCompareExchange(&g_log_lock_ready, 0, 0) != 0) {
    LeaveCriticalSection(&g_log_lock);
    LeaveCriticalSection(&g_log_io_lock);
  }

  if (to_close != NULL) {
    fclose(to_close);
  }
  if (to_close == NULL) {
    /* 只有控制台模式才需要断开会话；文件模式与 stdout 由 CRT 收尾。 */
    FreeConsole();
  }
}

/* 进程即将结束时的收尾：停刷新线程 + 释放控制台。可重复调用。
 *
 * 正常退出（窗口关闭 → 返回 main → CRT exit）由 atexit 触发；
 * pc_core_shutdown 走 TerminateProcess，**不会**执行 atexit，所以那里要显式调一次。 */
void pc_log_shutdown(void) {
  /* 先把行缓冲里剩下的日志刷出去：停线程之后没人再冲刷它了，
     而这些往往正是「退出前最后发生的事」，排查问题时最有用。
     未初始化时 pc_log_flush 是安全空操作。 */
  pc_log_flush();
  /* 再关掉日志开关。pc_task_impl_stop / pc_engine_stop 都是协作式停止、不等 join，
     所以下面 FreeConsole 时引擎线程可能仍在跑并打日志；开关清 0 后 pc_log 直接
     空返回，退出瞬间不会再有人 fwrite 已经失效的 stdout —— 这正是关窗闪退的根因。 */
  InterlockedExchange(&g_log_ready, 0);
  pc_log_stop_flush_thread();
  /* 崩溃日志句柄是常驻打开的（见 pc_crash_install），退出时收掉。 */
  if (g_crash_file != INVALID_HANDLE_VALUE) {
    CloseHandle(g_crash_file);
    g_crash_file = INVALID_HANDLE_VALUE;
  }
}

/* 控制台控制事件处理（A2）。
 *
 * 为什么需要：日志窗口虽然删掉了「关闭」菜单项，但控制台仍可能收到
 * CTRL_C / CTRL_BREAK（用户在控制台里按 Ctrl-C）、CTRL_CLOSE（任务栏/窗口
 * 关闭、注销、关机）。这些事件的默认处理是**直接结束进程**：此刻引擎的
 * 几十个工作线程可能正持着 g_queue_lock / g_side_lock / CRT 流锁，进程在
 * 任意指令处消失，磁盘上的记住密码文件也可能正好写到一半。
 *
 * 处理策略分两类：
 *   · Ctrl-C / Ctrl-Break → 直接吞掉（返回 TRUE）。这是 GUI 程序，控制台只是
 *     日志输出窗口，误按 Ctrl-C 不该把正在刷的单全打断。
 *   · 关闭 / 注销 / 关机 → 先把行缓冲刷盘、关掉日志开关，再交回默认处理
 *     （返回 FALSE）。这时进程注定要结束，能做的只是「别把最后一条日志丢了」
 *     和「别让别的线程再去写已经失效的 stdout」。
 *
 * 处理器运行在系统新建的线程上（不是崩溃现场），因此可以安全地用 CRT 与锁。 */
static BOOL WINAPI pc_log_ctrl_handler(DWORD type) {
  if (type == CTRL_C_EVENT || type == CTRL_BREAK_EVENT) {
    return TRUE; /* 吞掉：不打断刷单 */
  }
  pc_log_flush();
  InterlockedExchange(&g_log_ready, 0);
  return FALSE; /* 关闭/注销/关机：交回默认处理 */
}

/* 初始化体：只在 InitOnceExecuteOnce 里跑一次。
 *
 * 早先是 `if (g_log_ready) return; ... g_log_ready = 1;` 两步，且
 * InitializeCriticalSection 放在检查之后。目前只有 UI 线程会调，所以没出过事；
 * 但「日志会被几十个工作线程并发调用」这个前提一旦有人从后台线程调 pc_log_init，
 * 就会重复 InitializeCriticalSection（破坏正在使用的锁）并叠加刷新线程。
 * InitOnceExecuteOnce 由系统保证「恰好一次，其余线程等待完成」。 */
static BOOL CALLBACK pc_log_init_once(PINIT_ONCE once, PVOID param, PVOID* ctx) {
  (void)once;
  (void)param;
  (void)ctx;
  /* 行缓冲的锁：日志会被几十个工作线程并发调用，缓冲必须互斥。 */
  InitializeCriticalSection(&g_log_lock);
  /* 输出串行锁：见 g_log_io_lock 的说明（锁序固定 io → log）。 */
  InitializeCriticalSection(&g_log_io_lock);
  InterlockedExchange(&g_log_lock_ready, 1);

  /* 先试控制台；不行就降级到文件。两条路都失败才彻底静默。
   * 见 g_log_out 的说明：早先控制台失败就直接 return，日志全丢。 */
  if (pc_log_console_attach()) {
    g_log_out = stdout;
  } else {
    g_log_out = pc_log_open_file();
    if (g_log_out == NULL) return TRUE; /* 彻底没有输出去处：日志功能静默 */
  }
  InterlockedExchange(&g_log_ready, 1);

  /* 启动后台刷新线程，兜底「最后一条日志」的 200ms 超时刷新。 */
  g_log_stop_event = CreateEvent(NULL, TRUE, FALSE, NULL);
  if (g_log_stop_event != NULL) {
    g_log_flush_run = 1;
    g_log_flush_thread =
        CreateThread(NULL, 0, pc_log_flush_thread_proc, NULL, 0, NULL);
    if (g_log_flush_thread != NULL) {
      /* 句柄要留着等退出时 join，不能在这里关。 */
      atexit(pc_log_shutdown);
    } else {
      g_log_flush_run = 0;
    }
  }
  /* 建不出事件 / 线程时只是少了自动刷新，日志功能本身不受影响。 */
  return TRUE;
}

PC_API void pc_log_init(void) {
  InitOnceExecuteOnce(&g_log_init_once, pc_log_init_once, NULL, NULL);
}

/* 一行日志一次写出。
 *
 * 早先这里分三次 printf（前缀 / 正文 / 换行）——MSVC 的流锁是按调用加的，
 * 抢单引擎的工作线程并发打日志时，三行之间会互相穿插，输出成
 * `[12:00:00] >>>>>>>>>>[12:00:00] >>>>>>>>>>[手机号]...` 这种串行内容。
 * 现在先拼进一个缓冲区，补上换行后一次 fputs 写完，从根上避免错行；
 * 长日志（抢单成功会带整段响应体）按需扩容，不会被截断。 */
void pc_log(const char* fmt, ...) {
  SYSTEMTIME st;
  char stack_buf[1024];
  char* buf = stack_buf;
  size_t cap = sizeof(stack_buf);
  size_t len;
  int body_len;
  va_list ap;

  if (InterlockedCompareExchange(&g_log_ready, 0, 0) == 0 || fmt == NULL) return;

  GetLocalTime(&st);
  len = (size_t)snprintf(buf, cap, "[%02d:%02d:%02d] >>>>>>>>>>", st.wHour,
                         st.wMinute, st.wSecond);

  /* vsnprintf(NULL, 0, ...) 只量长度，不写任何东西。 */
  va_start(ap, fmt);
  {
    va_list probe;
    va_copy(probe, ap);
    body_len = vsnprintf(NULL, 0, fmt, probe);
    va_end(probe);
  }
  if (body_len < 0) body_len = 0;
  if (len + (size_t)body_len + 2 > cap) {
    size_t need = len + (size_t)body_len + 2;
    char* heap = (char*)malloc(need);
    if (heap != NULL) {
      /* 前缀是写在栈缓冲里的，换到堆缓冲必须把它搬过去 ——
         否则堆内存开头是未初始化的，strlen 会停在随机的 0 字节上，
         日志正文被截成一小段乱码。 */
      memcpy(heap, stack_buf, len + 1);
      buf = heap;
      cap = need;
    }
  }
  vsnprintf(buf + len, cap - len, fmt, ap);
  va_end(ap);

  {
    size_t used = strlen(buf);
    if (used + 2 > cap) used = cap - 2; /* 扩容失败被截断时的防御 */
    buf[used] = '\n';
    buf[used + 1] = '\0';

    /* 写进共享行缓冲（不再每行 fflush，见上面「行缓冲」的注释）。 */
    if (InterlockedCompareExchange(&g_log_lock_ready, 0, 0) == 0) {
      /* 日志还没初始化：本行无处可写，直接丢弃（与 g_log_ready==0 同语义）。 */
      if (buf != stack_buf) free(buf);
      return;
    }
    /* 【锁序：先 g_log_io_lock，后 g_log_lock】
     *
     * 早先整段都在 g_log_lock 里做，包括 fwrite / fflush 到控制台。控制台写入
     * 要过 conhost（滚动重绘、甚至用户拖选暂停），单次可达毫秒级；抢单活跃期
     * 每秒几十条日志，于是全部工作线程在这把锁上排队，引擎被日志拖慢。
     *
     * 现在 g_log_lock 只护内存（最多一次 8KB memcpy），真正的 fwrite 在
     * g_log_io_lock 里做，而 g_log_io_lock 只被「这一条要写盘的线程」持有。
     * 其它线程最多等一次 memcpy，随后立刻返回继续抢单。 */
    EnterCriticalSection(&g_log_io_lock);
    {
      size_t need = used + 1;      /* 含换行，不含结尾 0 */
      size_t take = 0;             /* 需要写出去的字节数（在 g_log_swap 里） */
      int direct = 0;              /* 1 = 这一条比整个缓冲还长，直写 */
      FILE* out = NULL;

      EnterCriticalSection(&g_log_lock);
      if (need > PC_LOG_BUF_CAP) {
        /* 单条日志比整个缓冲还长（抢单成功会带整段响应体）：先把已有的冲掉，
           再直写这一条 —— 不截断，也不把它拆成两半。 */
        take = log_take_locked();
        direct = 1;
        g_log_last_flush = GetTickCount64();
      } else {
        if (g_log_len + need > PC_LOG_BUF_CAP) {
          take = log_take_locked();
        }
        memcpy(g_log_buf + g_log_len, buf, need);
        g_log_len += need;
        if (g_log_len >= PC_LOG_FLUSH_BYTES ||
            GetTickCount64() - g_log_last_flush >= PC_LOG_FLUSH_MS) {
          take = log_take_locked();
        }
      }
      out = g_log_out;
      LeaveCriticalSection(&g_log_lock);

      if (take != 0 && out != NULL) {
        fwrite(g_log_swap, 1, take, out);
        fflush(out);
      }
      if (direct && out != NULL) {
        fwrite(buf, 1, need, out);
        fflush(out);
      }
    }
    LeaveCriticalSection(&g_log_io_lock);
  }
  if (buf != stack_buf) free(buf);
}

PC_API void pc_log_text(const char* text) {
  if (text == NULL) return;
  /* 走同一条路径：pc_log("%s", text) —— 不带格式串就不会有 % 被误解释的风险。 */
  pc_log("%s", text);
}

void pc_log_flush(void) {
  if (InterlockedCompareExchange(&g_log_ready, 0, 0) == 0) return;
  if (InterlockedCompareExchange(&g_log_lock_ready, 0, 0) == 0) return;
  /* 走 log_flush_all：内部按 io → log 的顺序拿锁，fwrite 在 io 锁里完成。 */
  log_flush_all();
}

/* 把一行日志直接落盘（exe 目录下的 pigeon.log，追加）。
 *
 * 刻意不复用 pc_log 的行缓冲 / 后台刷新线程：那些机制都依赖进程继续活着
 * （200ms 超时线程、atexit 收尾），而本函数的调用场景恰恰是「马上就要
 * ExitProcess」。每次独立 fopen/fclose，返回即落盘，进程随后的消失不影响它。 */
void pc_log_file(const char* fmt, ...) {
  SYSTEMTIME st;
  char dir[MAX_PATH];
  char path[MAX_PATH];
  FILE* f;
  va_list ap;

  if (fmt == NULL) return;

  GetLocalTime(&st);
  dir[0] = '\0';
  GetModuleFileNameA(NULL, dir, sizeof(dir));
  {
    char* slash = strrchr(dir, '\\');
    if (slash != NULL) slash[1] = '\0';
  }
  snprintf(path, sizeof(path), "%spigeon.log", dir);

  /* 【与正常日志路径串行化】
   *
   * 降级模式（控制台建不出来）下 g_log_out 就是**同一个** pigeon.log。两个
   * 独立的 FILE* 同时 append 到同一文件，写入会互相穿插，一条日志被另一条切成
   * 两半。退出路径上 pc_log_shutdown 也在动这个流。
   *
   * 这里用 g_log_io_lock 串行化（与 pc_log 的 fwrite 同一把锁，锁序 io → log，
   * 本函数只拿 io，不嵌套 log，因此不会与任何路径死锁）。锁未初始化时
   * （日志功能整个没起来）直接跳过串行化 —— 那时也没有别的写入者。 */
  {
    int locked = InterlockedCompareExchange(&g_log_lock_ready, 0, 0) != 0;
    if (locked) EnterCriticalSection(&g_log_io_lock);
    f = fopen(path, "a");
    if (f != NULL) {
      fprintf(f, "[%04d-%02d-%02d %02d:%02d:%02d] ", st.wYear, st.wMonth,
              st.wDay, st.wHour, st.wMinute, st.wSecond);
      va_start(ap, fmt);
      vfprintf(f, fmt, ap);
      va_end(ap);
      fprintf(f, "\n");
      fclose(f);
    }
    if (locked) LeaveCriticalSection(&g_log_io_lock);
  }
}

/* 把公告文本统一成 UTF-8 后输出到控制台（控制台已设为 CP_UTF8）。
 *
 * 服务端下发的公告编码并不稳定：有的线路给 UTF-8，有的给 GBK（系统 ANSI 代码页）。
 * 控制台是 CP_UTF8，所以：
 *   · 输入已是合法 UTF-8 —— 原样有界拷贝（不二次转码，否则会把合法 UTF-8 当
 *     GBK 又编一遍，反而乱码）；
 *   · 输入不是合法 UTF-8（典型是 GBK）—— 按 ANSI/GBK -> UTF-16 -> UTF-8 转码，
 *     修复「GBK 公告在 CP_UTF8 控制台下乱码」的问题。
 *
 * 这样无论服务端给哪种编码，控制台看到的都是同一份合法 UTF-8，分类与内容都正确显示。 */
static int pc_is_valid_utf8(const char* in, size_t n) {
  size_t i = 0;
  while (i < n) {
    unsigned char c = (unsigned char)in[i];
    size_t need;
    if (c < 0x80) {
      i++;
      continue;
    } else if ((c & 0xE0) == 0xC0) {
      need = 2; /* 110x xxxx */
    } else if ((c & 0xF0) == 0xE0) {
      need = 3; /* 1110 xxxx */
    } else if ((c & 0xF8) == 0xF0) {
      need = 4; /* 1111 0xxx */
    } else {
      return 0; /* 非法首字节（含 0x80–0xBF 续字节、0xF8+） */
    }
    if (i + need > n) return 0; /* 截断的序列 */
    for (size_t j = 1; j < need; j++) {
      if (((unsigned char)in[i + j] & 0xC0) != 0x80) return 0;
    }
    i += need;
  }
  return 1;
}

PC_API void pc_to_utf8(const char* in, char* out, size_t out_cap) {
  if (out == NULL || out_cap == 0) return;
  if (in == NULL) {
    out[0] = '\0';
    return;
  }

  size_t n = strlen(in);
  if (pc_is_valid_utf8(in, n)) {
    /* 已是合法 UTF-8：控制台同为 CP_UTF8，原样有界拷贝即可。 */
    if (n >= out_cap) n = out_cap - 1;
    memcpy(out, in, n);
    out[n] = '\0';
    return;
  }

  /* 非法 UTF-8：当成系统 ANSI 代码页（本机 GBK）转 UTF-8。
   * 分两步 GBK -> UTF-16 -> UTF-8；括号/空格/ASCII 分类名两种编码一致，不受影响。 */
  int wneed = MultiByteToWideChar(CP_ACP, 0, in, (int)n, NULL, 0);
  if (wneed <= 0) {
    out[0] = '\0';
    return;
  }
  wchar_t* wbuf = (wchar_t*)malloc((size_t)wneed * sizeof(wchar_t));
  if (wbuf == NULL) {
    out[0] = '\0';
    return;
  }
  if (MultiByteToWideChar(CP_ACP, 0, in, (int)n, wbuf, wneed) <= 0) {
    free(wbuf);
    out[0] = '\0';
    return;
  }
  int uneed = WideCharToMultiByte(CP_UTF8, 0, wbuf, wneed, NULL, 0, NULL, NULL);
  if (uneed <= 0) {
    free(wbuf);
    out[0] = '\0';
    return;
  }
  if ((size_t)uneed >= out_cap) {
    /* 有界截断必须落在字符边界上：按字节硬切会把汉字劈成半个，
     * 输出非法 UTF-8（控制台是 CP_UTF8，直接显示乱码）。
     * 逐步回退到「下一次转换不会切开多字节序列」的长度。 */
    uneed = (int)out_cap - 1;
    while (uneed > 0 &&
           WideCharToMultiByte(CP_UTF8, 0, wbuf, wneed, out, uneed, NULL,
                               NULL) <= 0) {
      uneed--;
    }
    if (uneed <= 0) {
      free(wbuf);
      out[0] = '\0';
      return;
    }
    WideCharToMultiByte(CP_UTF8, 0, wbuf, wneed, out, uneed, NULL, NULL);
    /* 再按 UTF-8 续字节回退，确保不留下半个字符。 */
    while (uneed > 0 && ((unsigned char)out[uneed - 1] & 0xC0u) == 0x80u) {
      uneed--;
    }
    out[uneed] = '\0';
    free(wbuf);
    return;
  }
  WideCharToMultiByte(CP_UTF8, 0, wbuf, wneed, out, uneed, NULL, NULL);
  out[uneed] = '\0';
  free(wbuf);
}

#else /* !_WIN32 */

PC_API void pc_log_init(void) {}

PC_API void pc_crash_install(void) {}

void pc_log(const char* fmt, ...) {
  (void)fmt;
}

void pc_log_flush(void) {}

void pc_log_file(const char* fmt, ...) { (void)fmt; }

void pc_log_shutdown(void) {}

#endif /* _WIN32 */
