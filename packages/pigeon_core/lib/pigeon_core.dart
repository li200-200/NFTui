// ---------------------------------------------------------------------------
// 鸽鸽软件助手 · C 核心的 Dart 入口
//
// 这一层只做两件事：
//   1. 把裸指针、内存释放这些 FFI 细节包起来，对界面暴露「传字符串、拿结果对象」
//      的普通 Dart 函数；
//   2. 把阻塞型调用（网络 / 线程启停）挪到后台 isolate。
//
// 这里不做任何业务判断 —— 业务规则全在 C 里。
//
// ---------------------------------------------------------------------------
// 【文件结构】
//
//   src/pigeon_core_native.dart   @Native 声明（只有声明，part 挂载）
//   src/types.dart                C 结构体与常量的 Dart 镜像
//   src/ffi_util.dart             UTF-8 入参分配/释放、出参读取
//
// 本文件（pigeon_core.dart）是**对外 API**：界面只 import 这一个库。
// 拆分后对外暴露的名字与拆分前完全一致，页面与测试一行都不用改。
//
// 【assetId 绑定】hook/build.dart 的 assetName 配成 'pigeon_core.dart'，
// 资产 ID 是 package:pigeon_core/pigeon_core.dart，与这个库的 URI 一致 ——
// 所以 @Native() 不用显式写 assetId 就能绑上。**改文件名会断掉这条绑定。**
//
// C 的导出函数名是 snake_case，Dart 的 lowerCamelCase 规则在这里必须让位：
// @Native 默认就拿 Dart 声明名当符号名，两者同名意味着不存在「字符串写错了」
// 这种错法。下面这行是为此开的口子，不是顺手关掉规则。
//
// ignore_for_file: non_constant_identifier_names
// ---------------------------------------------------------------------------
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'src/ffi_util.dart';
import 'src/types.dart';

export 'src/types.dart';

part 'src/pigeon_core_native.dart';

// ---------------------------------------------------------------------------
// 记住密码
// ---------------------------------------------------------------------------

/// 从「记住密码」文件里读出来的内容。
///
/// 文件不存在或损坏时 [remember] 为 false、[user] / [pwd] 为空 ——
/// 调用方不需要区分「没记住过」和「读坏了」，行为上都是空表单。
final class PcSavedCred {
  const PcSavedCred({
    required this.remember,
    required this.autoLogin,
    required this.user,
    required this.pwd,
  });

  final bool remember;
  final bool autoLogin;
  final String user;
  final String pwd;
}

/// 「记住密码」文件的默认路径（C 侧按平台给出）。
///
/// 用固定 512 字节缓冲读取：这个路径最多几十字节，不可能装不下。
String pcCredDefaultPath() {
  final Pointer<Utf8> buffer = calloc<Uint8>(512).cast<Utf8>();
  try {
    if (pc_cred_default_path(buffer, 512) != PcStatus.ok) {
      return '';
    }
    return buffer.toDartString();
  } finally {
    calloc.free(buffer);
  }
}

/// 保存「记住密码」。密码在 C 侧做一层混淆后落盘（不是真加密）。
///
/// [remember] 为 false 时写空记录，等价于清空之前记住的内容。
void pcCredSave({
  required String path,
  required String user,
  required String pwd,
  required bool remember,
  required bool autoLogin,
}) {
  withUtf8Args<void>(<String>[path, user, pwd], (List<Pointer<Utf8>> args) {
    pc_cred_save(
      args[0],
      args[1],
      args[2],
      remember ? 1 : 0,
      autoLogin ? 1 : 0,
    );
  });
}

/// 读取「记住密码」。
PcSavedCred pcCredLoad({required String path}) {
  return withUtf8Args<PcSavedCred>(<String>[path], (List<Pointer<Utf8>> args) {
    // 256 与 C 侧 pc_cred.c 的 PC_CRED_FIELD_MAX 一致。
    final Pointer<Utf8> user = calloc<Uint8>(256).cast<Utf8>();
    final Pointer<Utf8> pwd = calloc<Uint8>(256).cast<Utf8>();
    final Pointer<Int32> remember = calloc<Int32>();
    final Pointer<Int32> autoLogin = calloc<Int32>();
    try {
      pc_cred_load(args[0], user, 256, pwd, 256, remember, autoLogin);
      return PcSavedCred(
        remember: remember.value != 0,
        autoLogin: autoLogin.value != 0,
        user: user.toDartString(),
        pwd: pwd.toDartString(),
      );
    } finally {
      calloc.free(user);
      calloc.free(pwd);
      calloc.free(remember);
      calloc.free(autoLogin);
    }
  });
}

// ---------------------------------------------------------------------------
// 第一段：表单校验（同步，不碰网络）
// ---------------------------------------------------------------------------

/// 登录表单校验。纯本地计算，几微秒返回，**不发任何请求**。
///
/// 页面第一段调它：表单没过就立刻把对应输入框变红抖动、不进「提交中」。
/// 为一个纯本地判定去等一次后台往返是没有道理的。
///
/// 校验规则只有 C 侧那一份，页面不要自己再抄一遍。
PcFormResult pcAuthValidateLogin({required String user, required String pwd}) =>
    _callValidate(
      <String>[user, pwd],
      (List<Pointer<Utf8>> args, Pointer<PcFormResultNative> out) =>
          pc_auth_validate_login(args[0], args[1], out),
    );

/// 注册表单校验。四个字段的槽位一次拿全。
PcFormResult pcAuthValidateRegister({
  required String user,
  required String pwd,
  required String pwd2,
  required String card,
}) => _callValidate(
  <String>[user, pwd, pwd2, card],
  (List<Pointer<Utf8>> args, Pointer<PcFormResultNative> out) =>
      pc_auth_validate_register(args[0], args[1], args[2], args[3], out),
);

/// 充值表单校验。
PcFormResult pcAuthValidateRecharge({
  required String user,
  required String confirm,
  required String card,
}) => _callValidate(
  <String>[user, confirm, card],
  (List<Pointer<Utf8>> args, Pointer<PcFormResultNative> out) =>
      pc_auth_validate_recharge(args[0], args[1], args[2], out),
);

PcFormResult _callValidate(
  List<String> args,
  int Function(List<Pointer<Utf8>>, Pointer<PcFormResultNative>) invoke,
) {
  final Pointer<PcFormResultNative> out = calloc<PcFormResultNative>();
  try {
    return withUtf8Args<PcFormResult>(args, (List<Pointer<Utf8>> pointers) {
      invoke(pointers, out);
      // toDart() 必须在这里做：出了 withUtf8Args 只是字符串被释放，
      // 但 out 也在 finally 里释放，别把裸引用带出去。
      return out.ref.toDart();
    });
  } finally {
    calloc.free(out);
  }
}

// ---------------------------------------------------------------------------
// 第二段：提交给服务端
// ---------------------------------------------------------------------------

/// 三个提交接口的编译期选择子。
///
/// 不用函数指针传「要调哪个」：闭包跨不了 isolate 边界，而这次调用必须
/// 挪到后台 isolate 里跑。用一个枚举，捕获的东西就全是可发送的。
enum _AuthKind { login, register, recharge }

/// 登录：提交给服务端验证。成功时 [PcAuthResult.data] 是 Token。
///
/// 【注意】这是真实网络请求，最长可能等 25 秒（连接超时 10s + 读取超时 15s）。
/// 页面应当先调 [pcAuthValidateLogin]，表单过了再调它。
Future<PcAuthResult> pcAuthLogin({required String user, required String pwd}) =>
    _callAuth(_AuthKind.login, <String>[user, pwd]);

/// 注册：提交给服务端。用户名是否已被占用由服务端裁决。
Future<PcAuthResult> pcAuthRegister({
  required String user,
  required String pwd,
  required String pwd2,
  required String card,
}) => _callAuth(_AuthKind.register, <String>[user, pwd, pwd2, card]);

/// 充值：提交给服务端。
Future<PcAuthResult> pcAuthRecharge({
  required String user,
  required String confirm,
  required String card,
}) => _callAuth(_AuthKind.recharge, <String>[user, confirm, card]);

/// 真正落到 FFI 的那一步。同步、阻塞，调用方负责决定在哪个线程上跑它。
PcAuthResult _invokeAuth(_AuthKind kind, List<String> args) {
  final Pointer<PcAuthResultNative> out = calloc<PcAuthResultNative>();
  try {
    return withUtf8Args<PcAuthResult>(args, (List<Pointer<Utf8>> p) {
      switch (kind) {
        case _AuthKind.login:
          pc_auth_login(p[0], p[1], out);
        case _AuthKind.register:
          pc_auth_register(p[0], p[1], p[2], p[3], out);
        case _AuthKind.recharge:
          pc_auth_recharge(p[0], p[1], p[2], out);
      }
      // toDart() 必须在这里做：出了 withUtf8Args 只是字符串被释放，
      // 但 out 也在 finally 里释放，别把裸引用带出去。
      return out.ref.toDart();
    });
  } finally {
    calloc.free(out);
  }
}

/// 提交入口：一律挪到后台 isolate。
///
/// 这三个接口会阻塞到请求结束（最长 25 秒），放在 UI 线程上就是整个界面卡死。
/// 这里没有「本地捷径」可走了 —— 已经不存在不发请求也能给出结论的路径。
///
/// 副作用是 widget 测试等不到它的结果（测试跑在 FakeAsync 里，真实 isolate
/// 的完成回调不被驱动），所以页面里「校验 → 红框」那条链路走的是上面那组
/// 同步校验入口，而不是这里。
Future<PcAuthResult> _callAuth(_AuthKind kind, List<String> args) {
  return Isolate.run(() => _invokeAuth(kind, args));
}

/// 获取系统公告并逐条输出到运行日志。同步阻塞（网络请求）。
int pcAuthNotice() => pc_auth_notice();

/// 把公告获取交给后台 isolate 执行（避免网络阻塞 UI 线程）。
Future<int> pcAuthNoticeAsync() => Isolate.run(pcAuthNotice);

// ---------------------------------------------------------------------------
// 心跳 / 退出收尾
// ---------------------------------------------------------------------------

/// 启动登录心跳：登录成功进入工作台后调用。
///
/// 起一个后台循环线程，每 10 分钟调一次 timeout.lg 保活（用的是登录 / 注册 /
/// 充值响应里采用来的会话串）。幂等：已在跑时重复调用无副作用。
///
/// 【注意】这是 C 侧唯一管后台线程的接口，属「C 侧不起线程」约定的显式例外。
int pcHeartbeatStart() => pc_heartbeat_start();

/// 停止登录心跳：离开工作台 / 关闭软件时调用。
///
/// 协作式：立即返回，线程在网络调用返回后自行退出（最长约 25s）。
/// 需要确认真的收干净时，用 [pcHeartbeatIsRunning] 轮询。
int pcHeartbeatStop() => pc_heartbeat_stop();

/// 心跳线程是否仍在跑（true=在跑）。
bool pcHeartbeatIsRunning() {
  final Pointer<Int32> out = calloc<Int32>();
  try {
    if (pc_heartbeat_is_running(out) != 0) return false;
    return out.value != 0;
  } finally {
    calloc.free(out);
  }
}

/// 退出收尾：停心跳 → 停任务/抢单引擎 → 停日志刷新线程并释放日志控制台 →
/// 终止进程。全程不依赖窗口消息循环，退出是确定的，不会再残留 conhost.exe。
///
/// 【重要】调用后进程立即结束，**必须作为退出流程的最后一句**，
/// 之后不能有任何代码（包括 await）。
int pcCoreShutdown(int nowMs) => pc_core_shutdown(nowMs);

// ---------------------------------------------------------------------------
// 日志
// ---------------------------------------------------------------------------

/// 初始化运行日志控制台（不可关闭）。启动时调用一次。
void pcLogInit() => pc_log_init();

/// 往运行日志里写一行（给 Dart 侧用：FFI 传不了可变参数）。
///
/// 未初始化日志时是安全的空操作，不会抛异常。
void pcLog(String text) {
  final Pointer<Utf8> p = text.toNativeUtf8();
  try {
    pc_log_text(p);
  } finally {
    // toNativeUtf8() 用的是 malloc，必须用 malloc.free 配对（见 ffi_util.dart）。
    malloc.free(p);
  }
}

// ---------------------------------------------------------------------------
// ABI 自检（C 结构体尺寸 / 偏移 vs Dart 镜像）
// ---------------------------------------------------------------------------

/// `pc_form_result` 的字节数（C 侧 6 个 int32）。
///
/// 单独导出成常量是为了让测试能直接断言，而不是只能靠 [pcAbiCheck] 往日志里
/// 写一行字 —— 日志断言不了「没写」和「写对了」的区别。
final int sizeOfFormResult = sizeOf<PcFormResultNative>();

/// `pc_auth_result` 的字节数：status(4) + form(24) + message(256) + data(512)。
final int sizeOfAuthResult = sizeOf<PcAuthResultNative>();

/// 读 C 侧实际编译出来的结构体尺寸数组。
///
/// 顺序与 C 的 `pc_abi_probe` 一致：`[pc_form_result, pc_auth_result]`。
/// 返回空列表表示调用失败（理论上不会 —— 只有传空指针才会）。
List<int> pcAbiProbe() {
  const int count = 2;
  final Pointer<Int32> buf = calloc<Int32>(count);
  try {
    final int n = pc_abi_probe(buf, count);
    if (n <= 0) return const <int>[];
    return <int>[for (int i = 0; i < n; i++) buf[i]];
  } finally {
    calloc.free(buf);
  }
}

/// 逐项比对 C 侧实际布局与 Dart 镜像；不一致就写进运行日志。
///
/// 为什么要有这一步：Dart 的结构体是手写镜像，FFI 按偏移读，两边任何一处
/// lens 宏写错都不会编译报错。后果是「读出来的字符串尾巴上粘着别的字段」
/// 「数字变成天文数字」，严重时越界读原生内存直接崩 —— 这类问题靠看代码
/// 极难发现，靠运行时表现也很难倒推。启动时对一次，几十微秒，把不确定性变成
/// 一条明确的日志。失败不影响功能（只是说明布局漂移了），所以这里不抛异常。
///
/// 【本工程只移植了验证页依赖的 C 模块】
/// 原 snap 工程还有 task / shide / engine 三套业务，它们的结构体在这里不存在，
/// 所以比对项从 9 项减到 2 项。**顺序必须与 C 侧 pc_abi_probe 完全一致** ——
/// 以后移植那些模块时，要把这里的项按原工程顺序补回去。
void pcAbiCheck() {
  const List<String> names = <String>[
    'pc_form_result.size',
    'pc_auth_result.size',
  ];
  // Dart 侧期望值（按 C 的布局规则手算，与 pc_abi_probe 的输出一一对应）。
  final List<int> expect = <int>[
    sizeOf<PcFormResultNative>(),
    sizeOf<PcAuthResultNative>(),
  ];
  final Pointer<Int32> buf = calloc<Int32>(names.length);
  try {
    final int n = pc_abi_probe(buf, names.length);
    if (n <= 0) {
      pcLog('ABI 自检未能执行（code=$n）');
      return;
    }
    final List<String> bad = <String>[];
    for (int i = 0; i < n && i < names.length; i++) {
      if (buf[i] != expect[i]) {
        bad.add('${names[i]} C=${buf[i]} Dart=${expect[i]}');
      }
    }
    if (bad.isEmpty) {
      pcLog('ABI 自检通过（$n 项）');
    } else {
      // 只有这一条需要醒目：布局漂移会让 FFI 读到错位数据。
      pcLog('ABI 自检失败：${bad.join('; ')} —— 请同步 pigeon_core.h 与 types.dart');
    }
  } finally {
    calloc.free(buf);
  }
}

/// 安装崩溃处理器：崩溃/闪退时写 crash.log。启动时调用一次。
void pcCrashInstall() => pc_crash_install();
