// ---------------------------------------------------------------------------
// C 导出函数的外部声明（FFI 绑定）—— 只有声明，没有业务
//
// 从 pigeon_core.dart 拆出来的原因：那个文件原本 1231 行，@Native 声明与
// 「面向界面的封装函数」混在一起，找一条声明要在几百行 external 里翻。
//
// 【assetId 绑定】hook/build.dart 把 assetName 配成 'pigeon_core.dart'，
// 资产 ID 因此是 package:pigeon_core/pigeon_core.dart，与 pigeon_core.dart
// 这个库的 URI 一致 —— 所以 @Native() 不用显式写 assetId 就能绑上。
//
// 本文件被 pigeon_core.dart 用 `part` 挂载（不是 import），所以：
//   · 这里的 external 声明会并入 pigeon_core.dart 的库作用域；
//   · 调用点不需要任何前缀，与拆分前完全一致；
//   · 对外 API 不变 —— 界面代码一行都不用改。
//
// 【命名规则】C 导出名是 snake_case，Dart 侧的 lowerCamelCase 规则在这里必须
// 让位：@Native 默认拿 Dart 声明名当符号名，两者同名意味着不存在「字符串写错
// 了」这种错法。下面的 ignore 是为此开的口子，不是顺手关掉规则。
//
// 【新增一个 C 接口】三处都要动，缺一处会以「符号找不到 / 链接期未定义」暴露：
//   1. src/pigeon_core.h      声明导出函数
//   2. src/*.c                实现
//   3. hook/build.dart        sources 列表里登记新的 .c（如果是新文件）
//   4. 本文件                 加 @Native 声明
//   5. pigeon_core_api.dart   加面向界面的封装（参数校验 + 内存释放）
//
// 【为什么用 part 而不是 import】
// @Native() 不写 assetId 时，资产 ID 由**声明所在库的 URI**推导。hook/build.dart
// 把 assetName 配成 'pigeon_core.dart'，所以只有声明位于库
// `package:pigeon_core/pigeon_core.dart` 里，默认 assetId 才等于
// `package:pigeon_core/pigeon_core.dart`、运行时才绑得上。
//
// part 文件属于**同一个库**（库 URI 不变），所以这里的 external 声明与写在
// pigeon_core.dart 里完全等价；如果改成 import 一个单独的 src 库，默认 assetId
// 会变成 package:pigeon_core/src/pigeon_core_native.dart —— 编译能过，
// 运行时却找不到符号。**这条是硬约束，不要改成 import。**
//
// ignore_for_file: non_constant_identifier_names
// ---------------------------------------------------------------------------
part of 'package:pigeon_core/pigeon_core.dart';

// ---------------------------------------------------------------------------
// 认证（BSPHP）
// ---------------------------------------------------------------------------

@Native<
  Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<PcAuthResultNative>)
>()
external int pc_auth_login(
  Pointer<Utf8> user,
  Pointer<Utf8> pwd,
  Pointer<PcAuthResultNative> out,
);

@Native<
  Int32 Function(
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<PcAuthResultNative>,
  )
>()
external int pc_auth_register(
  Pointer<Utf8> user,
  Pointer<Utf8> pwd,
  Pointer<Utf8> pwd2,
  Pointer<Utf8> card,
  Pointer<PcAuthResultNative> out,
);

@Native<
  Int32 Function(
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<PcAuthResultNative>,
  )
>()
external int pc_auth_recharge(
  Pointer<Utf8> user,
  Pointer<Utf8> confirm,
  Pointer<Utf8> card,
  Pointer<PcAuthResultNative> out,
);

@Native<
  Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<PcFormResultNative>)
>()
external int pc_auth_validate_login(
  Pointer<Utf8> user,
  Pointer<Utf8> pwd,
  Pointer<PcFormResultNative> out,
);

@Native<
  Int32 Function(
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<PcFormResultNative>,
  )
>()
external int pc_auth_validate_register(
  Pointer<Utf8> user,
  Pointer<Utf8> pwd,
  Pointer<Utf8> pwd2,
  Pointer<Utf8> card,
  Pointer<PcFormResultNative> out,
);

@Native<
  Int32 Function(
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<PcFormResultNative>,
  )
>()
external int pc_auth_validate_recharge(
  Pointer<Utf8> user,
  Pointer<Utf8> confirm,
  Pointer<Utf8> card,
  Pointer<PcFormResultNative> out,
);

@Native<Int32 Function()>(symbol: 'pc_auth_notice')
external int pc_auth_notice();

// ---------------------------------------------------------------------------
// 心跳
// ---------------------------------------------------------------------------

@Native<Int32 Function()>(symbol: 'pc_heartbeat_start')
external int pc_heartbeat_start();

@Native<Int32 Function()>(symbol: 'pc_heartbeat_stop')
external int pc_heartbeat_stop();

@Native<Int32 Function(Pointer<Int32>)>(symbol: 'pc_heartbeat_is_running')
external int pc_heartbeat_is_running(Pointer<Int32> outRunning);

// ---------------------------------------------------------------------------
// 记住密码
// ---------------------------------------------------------------------------

@Native<Int32 Function(Pointer<Utf8>, Int32)>()
external int pc_cred_default_path(Pointer<Utf8> out, int capacity);

@Native<
  Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32, Int32)
>()
external int pc_cred_save(
  Pointer<Utf8> path,
  Pointer<Utf8> user,
  Pointer<Utf8> pwd,
  int remember,
  int autoLogin,
);

@Native<
  Int32 Function(
    Pointer<Utf8>,
    Pointer<Utf8>,
    Int32,
    Pointer<Utf8>,
    Int32,
    Pointer<Int32>,
    Pointer<Int32>,
  )
>()
external int pc_cred_load(
  Pointer<Utf8> path,
  Pointer<Utf8> outUser,
  int userCap,
  Pointer<Utf8> outPwd,
  int pwdCap,
  Pointer<Int32> outRemember,
  Pointer<Int32> outAutoLogin,
);

// ---------------------------------------------------------------------------
// 退出收尾
// ---------------------------------------------------------------------------

@Native<Int32 Function(Int64)>(symbol: 'pc_core_shutdown')
external int pc_core_shutdown(int nowMs);

// ---------------------------------------------------------------------------
// 日志 / 崩溃 / ABI 自检
// ---------------------------------------------------------------------------

@Native<Void Function()>(symbol: 'pc_log_init')
external void pc_log_init();

@Native<Void Function(Pointer<Utf8>)>(symbol: 'pc_log_text')
external void pc_log_text(Pointer<Utf8> text);

@Native<Void Function()>(symbol: 'pc_crash_install')
external void pc_crash_install();

@Native<Int32 Function(Pointer<Int32>, Int32)>()
external int pc_abi_probe(Pointer<Int32> out, int cap);
