/* ---------------------------------------------------------------------------
 * 鸽鸽软件助手 · C 核心对外契约
 *
 * 这是 Dart 侧唯一需要认的 ABI。界面文案、布局、动画全部留在 Dart，
 * 这里只放「业务判定」与「业务状态」。
 *
 * 约定 —— 后续新增的每个导出函数都必须遵守：
 *   1. 字符串一律 UTF-8。入参由调用方持有，C 侧只读，绝不保存指针。
 *   2. 出参字符串写进调用方给的缓冲，C 侧不 malloc 跨边界（谁分配谁释放，
 *      边界上没有所有权歧义）。
 *   3. 入参非法返回错误码，绝不崩溃；缓冲不足返回 PC_ERR_BUFFER_SMALL
 *      并回填所需长度，调用方可以扩容重试。
 *   4. 全部函数是同步短调用，不阻塞、不起线程。
 *   5. 出参结构体一定会被完整写一遍，调用方不会读到未初始化的字段。
 *
 * 改动这个文件时，必须同步改 Dart 侧镜像：lib/src/types.dart。
 * 两边不一致不会编译报错，只会表现成「莫名其妙的判定结果」。
 * ------------------------------------------------------------------------- */

#ifndef PIGEON_CORE_H
#define PIGEON_CORE_H

#include <stdint.h>

#if defined(_WIN32)
#  if defined(PIGEON_CORE_BUILD)
#    define PC_API __declspec(dllexport)
#  else
#    define PC_API __declspec(dllimport)
#  endif
#else
#  define PC_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ===========================================================================
 * 状态码
 * ========================================================================= */

#define PC_OK 0

/* ---- 通用错误 ---- */
#define PC_ERR_INVALID_ARG (-1)  /* 入参为空指针等 */
#define PC_ERR_BUFFER_SMALL (-2) /* 调用方给的缓冲装不下 */

/* ---- 表单 / 业务结果 ----
 *
 * 这几个是「正常的业务结论」，不是程序错误：调用方应当把它们当成
 * 有意义的返回值处理，而不是当异常。它们的共性是 form 字段一定有意义。 */
#define PC_ERR_FORM (-10)      /* 表单没通过；out 里标了具体是哪几个字段 */
#define PC_ERR_MAP_EMPTY (-13) /* 要加入的地图是空的 */

/* ---- 两类失败 ----
 *
 * 分开的原因很实际：界面上「连不上服务器」和「服务端拒绝了这个账号」该给用户
 * 完全不同的引导（一个提示检查网络/稍后重试，一个提示核对账号）。只靠 message
 * 文本区分，调用方就得去匹配中文，那是把文案当协议用。
 *
 * 注意：账号密码不对、用户名已被占用这类结论现在**没有**独立的状态码 ——
 * 它们全部由服务端裁决，落在 PC_ERR_SERVER 上，具体原因在 message 里
 * （服务端返回的原始提示语）。本地不再有「不发请求也能判定账号」的分支，
 * 所以那种状态码也就不存在了。 */
#define PC_ERR_NETWORK (-14) /* 请求没走通：DNS/连接/超时/非 200。可重试 */
#define PC_ERR_SERVER (-15)  /* 服务端明确拒绝，错误码已翻译进 message */
#define PC_ERR_IO (-16)      /* 本地文件读写失败（记住密码的持久化等） */

/* ===========================================================================
 * 表单字段级判定
 * ========================================================================= */

enum {
  PC_FIELD_OK = 0,
  PC_FIELD_EMPTY,     /* 没填 */
  PC_FIELD_TOO_SHORT, /* 长度不够（下限） */
  PC_FIELD_MISMATCH,  /* 两次输入不一致 */
  PC_FIELD_BAD_CARD,  /* 卡密格式不对 */
  PC_FIELD_BAD_LENGTH,/* 长度不落在要求的区间里（用户名要求 6-16） */
  PC_FIELD_BAD_CHARS, /* 含不允许的字符（用户名只能字母数字） */
  PC_FIELD_TOO_LONG   /* 超过本地上限（防止超长输入被传输层静默截断） */
};

/* 一次表单校验的逐字段结论。
 *
 * 用「每个字段一个槽位」而不是「返回第一个错误」：界面要求每个出错的输入框
 * 各自变红抖动，一次提交可能同时有两个字段出错，只报一个不够用。
 *
 * 每个字段各有独立槽位，不复用：
 *   user    三个页面都是「用户名」
 *   pwd     注册/登录的密码
 *   pwd2    注册页的「确认密码」（只在本地做一致性比对）
 *   pwd_acc 充值页的「账号密码」（BSPHP 的 chong.lg 需要 userpwd，
 *           实测传空会回 code=1009「密码错误」）
 *   card    卡密
 * 早先 pwd2 一槽两用（注册=确认密码 / 充值=账号密码），语义会随页面漂移，
 * 任何按槽位名通用渲染的代码都会在充值页显示成「两次输入不一致」。 */
typedef struct {
  int32_t user;    /* PC_FIELD_* */
  int32_t pwd;     /* PC_FIELD_* */
  int32_t pwd2;    /* PC_FIELD_* */
  int32_t card;    /* PC_FIELD_* */
  int32_t pwd_acc; /* PC_FIELD_* 充值页「账号密码」 */
  int32_t form_ok; /* 1 = 全部槽位通过 */
} pc_form_result;

/* ===========================================================================
 * 认证调用的完整结果
 * ========================================================================= */

/* 提示语与返回数据的容量。
 *
 * 定长字符数组而不是指针：出参内存由调用方提供，C 侧不 malloc 跨边界。
 * 服务端最长的官方提示语在 60 个汉字以内（UTF-8 三字节/字），256 留了余量；
 * data 放的是返回原文（登录成功时是 Token，官方要求 16 位），512 足够。 */
#define PC_AUTH_MSG_LEN 256
#define PC_AUTH_DATA_LEN 512

/* 一次认证调用的完整结论。
 *
 * 改动这个结构体必须同步改 Dart 侧镜像 lib/src/types.dart —— FFI 按偏移读，
 * 两边不一致不会编译报错，只会读到错位的数据。 */
typedef struct {
  /* 顶层结论，PC_OK / PC_ERR_*。 */
  int32_t status;

  /* 逐字段结论。status 是 PC_ERR_NETWORK / PC_ERR_SERVER 时 form_ok 也是 1：
     表单本身是通过的，问题出在账号或网络上，不是填法。 */
  pc_form_result form;

  /* 给用户看的提示语。成功时是「登录成功」这类短句；
     失败时是翻译过的服务端错误码，未收录的码原样呈现。 */
  char message[PC_AUTH_MSG_LEN];

  /* 服务端返回的原文。登录成功时就是 Token。
     不做任何格式校验 —— 服务端返回什么就是什么。 */
  char data[PC_AUTH_DATA_LEN];
} pc_auth_result;

/* ===========================================================================
 * 导出函数
 * ========================================================================= */

/* ---- 第一段：表单校验（同步，不碰网络） ----
 *
 * 这三个函数只做「填法对不对」，返回 PC_OK 或 PC_ERR_FORM，并一定把
 * out 完整写一遍。**它们绝不发起任何请求**，几微秒返回。
 *
 * 存在的理由有两层：
 *   1. 交互上，输入不完整时应当立刻红框抖动、不进「提交中」——
 *      没道理为一个纯本地判定去等一次网络往返；
 *   2. 工程上，下面那三个提交接口会阻塞（最长达 25 秒），必须放到后台
 *      isolate 里跑，而 widget 测试跑在 FakeAsync 里等不到真实 isolate 的结果。
 *      校验能同步拿到，页面里「校验 → 红框」这条链路才测得了。
 *
 * 校验规则只有一份，就在这两个入口共用的实现里 —— 页面不需要、也不允许
 * 自己再抄一遍规则。 */
PC_API int32_t pc_auth_validate_login(const char* user, const char* pwd,
                                      pc_form_result* out);

PC_API int32_t pc_auth_validate_register(const char* user, const char* pwd,
                                         const char* pwd2, const char* card,
                                         pc_form_result* out);

PC_API int32_t pc_auth_validate_recharge(const char* user, const char* confirm,
                                         const char* card,
                                         pc_form_result* out);

/* ---- 第二段：提交（同步阻塞，发真实请求） ----
 *
 * 返回 PC_OK / PC_ERR_FORM / PC_ERR_NETWORK / PC_ERR_SERVER，
 * 并把完整结论写进 out。
 *
 * 【重要】这三个函数会**阻塞**到请求完成（最长 = 连接超时 10s +
 * 读取超时 15s）。调用方必须放到后台线程/isolate 里跑，
 * 不能在 UI 线程直接调 —— 那等于整个界面卡死 25 秒。
 *
 * 表单没过时它们会走第一段同样的校验并直接返回 PC_ERR_FORM，
 * 不产生任何网络流量；但调用方仍应当先调第一段，以获得即时反馈。
 */

/* 登录。user 会 trim，pwd 不 trim。
   成功时 out->data 是服务端返回的 Token。 */
PC_API int32_t pc_auth_login(const char* user, const char* pwd,
                             pc_auth_result* out);

/* 注册。user / card 会 trim，pwd / pwd2 不 trim。
   pwd2 只在本地比对（服务端接口没有这个参数）。 */
PC_API int32_t pc_auth_register(const char* user, const char* pwd,
                                const char* pwd2, const char* card,
                                pc_auth_result* out);

/* 充值。三个字段全部 trim。user 只判空，没有长度校验。 */
PC_API int32_t pc_auth_recharge(const char* user, const char* confirm,
                                const char* card, pc_auth_result* out);

/* 系统公告（api_type "1"）。获取公告并逐条输出到运行日志。 */
PC_API int32_t pc_auth_notice(void);

/* ---- 登录心跳（后台保活） ----
 *
 * 登录成功进入工作台后启动：起一个循环线程，每 10 分钟调一次 timeout.lg
 * 保活 / 更新在线状态；离开工作台或关闭软件时停止。
 *
 * 【显式例外】这两个函数管理后台线程，打破了本文件顶部「不起线程」的通用约定
 * （与抢单引擎同类）。stop 是协作式的：只置停止标志并唤醒等待，**立即返回**，
 * 线程在网络调用返回后自行退出（最长约 25s），调用方可用 is_running 轮询确认。
 *
 * start 幂等：已在跑时重复调用返回 PC_OK，不会叠加线程。
 * 返回 PC_OK / PC_ERR_SERVER（起线程失败）。 */
PC_API int32_t pc_heartbeat_start(void);
PC_API int32_t pc_heartbeat_stop(void);

/* 心跳线程是否仍在跑。out_running 收 1（在跑）/ 0（已停 / 从未启动）。 */
PC_API int32_t pc_heartbeat_is_running(int32_t* out_running);

/* ---- 退出收尾（一次性，调用后进程立即结束） ----
 *
 * 把「退出要做的事」收敛到一个入口，让正常关闭与其他退出路径走完全相同的收尾：
 *   停心跳 → 停任务/抢单引擎 → 停日志刷新线程并 FreeConsole 释放日志控制台 →
 *   TerminateProcess(0) 硬终止。
 *
 * 存在的理由：不再依赖「窗口销毁 → 消息循环退出 → main 返回 → CRT exit」这条
 * 隐式链去回收资源。只要有一环卡住（窗口回调阻塞、后台线程握着句柄），
 * conhost.exe / 线程就会残留。这里显式收尾 + 硬终止，退出是确定的。
 *
 * 用 TerminateProcess 而非 ExitProcess：后者要等所有线程走到各自的
 * DllMain(PROCESS_DETACH)，而引擎线程可能正卡在最长 25s 的网络调用里，
 * 会让「点关闭」看起来僵住。终止前该停的都停了，剩下交给内核回收更确定。
 *
 * 必须作为退出流程的**最后一步**调用，之后进程不会再继续执行。
 * now_ms 用于协作式停止任务状态机（与 pc_task_stop 同义）。 */
PC_API int32_t pc_core_shutdown(int64_t now_ms);

/* ===========================================================================
 * 记住密码
 * ========================================================================= */

/* 默认存储路径：%LOCALAPPDATA%\pigeon_assist_cred.dat。
   cap 装不下返回 PC_ERR_BUFFER_SMALL。 */
PC_API int32_t pc_cred_default_path(char* out, int32_t cap);

/* 保存账号密码。remember 为 0 时写空记录（等价于清空）。
   返回 PC_OK / PC_ERR_IO。 */
PC_API int32_t pc_cred_save(const char* path, const char* user, const char* pwd,
                            int32_t remember, int32_t auto_login);

/* 读取。文件不存在或损坏 → remember=0、空账号密码、返回 PC_OK。
   任一出参可为 NULL。 */
PC_API int32_t pc_cred_load(const char* path, char* out_user, int32_t user_cap,
                            char* out_pwd, int32_t pwd_cap, int32_t* out_remember,
                            int32_t* out_auto_login);

/* ===========================================================================
 * ABI 自检
 * ========================================================================= */

/* 把本 DLL 实际编译出来的结构体尺寸与字段偏移写进 out（int32 数组），
 * 返回写入的条数；cap 不够返回 PC_ERR_BUFFER_SMALL。
 *
 * 为什么需要：Dart 侧的结构体是手写镜像，FFI 按偏移读。两边任何一个 lens 宏
 * 改错（比如 C 侧 PC_SHIDE_MSG_LEN 从 256 改成 128 而 Dart 没跟），都不会有
 * 任何编译期报错 —— 运行时表现为「读出来的字符串后面跟着别的字段」「数字变成
 * 天文数字」这类极难定位的现象，严重时还会越界读原生内存直接崩。
 * Dart 侧启动时调一次，逐项与 sizeOf<T>() 比对，不一致就在运行日志里明确报出来。
 *
 * 顺序固定（见 pigeon_core.c 的 pc_abi_probe 实现），追加只能加在末尾。 */
PC_API int32_t pc_abi_probe(int32_t* out, int32_t cap);

/* ===========================================================================
 * 运行日志（不可关闭的控制台窗口）
 * ========================================================================= */

/* 初始化日志控制台（不可关闭）并重定向 stdout。可重复调用。 */
PC_API void pc_log_init(void);

/* 安装崩溃处理器：进程崩溃/闪退时把异常信息写进 crash.log。可重复调用。 */
PC_API void pc_crash_install(void);

/* 输出一条现成的文本日志（不带格式串）。给 Dart 侧用：FFI 传不了可变参数。 */
PC_API void pc_log_text(const char* text);

#ifdef __cplusplus
}
#endif

#endif /* PIGEON_CORE_H */
