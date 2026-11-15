// ---------------------------------------------------------------------------
// native assets 构建钩子
//
// Dart SDK 会自动发现并执行这个文件（package:hooks 的 build() 负责与 SDK 握手），
// 编译产物作为 CodeAsset 随应用一起打包，Dart 侧的 @Native() 运行时直接绑定。
//
// 为什么不用 CMake 编译 C：
//   windows/CMakeLists.txt 里开着 /W4 /WX（警告即错误）与 /EHsc，C 代码混进去
//   要同时伺候「零警告」和 MSBuild 的中文路径问题。走 CLibrary 则完全独立，
//   只受这里的参数控制。
// ---------------------------------------------------------------------------
import 'dart:io' show Platform;

import 'package:code_assets/code_assets.dart' show LinkModePreference;
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    // 本工作区不做交叉编译（host == target），所以直接看宿主平台。
    //
    // 刻意不用 input.config.code.targetOS：那个访问器的形态在 hooks 2.0.2 与
    // 2.2.0 之间变过，同一份 hook 源码必须能同时编译过这两套。Platform 没有
    // 这个问题。
    final bool isWindows = Platform.isWindows;

    final CLibrary library = CLibrary(
      name: 'pigeon_core',
      // assetName 决定了资产 ID：package:pigeon_core/<assetName>。
      // 这里刻意与 lib/pigeon_core.dart 同名 —— 这样 Dart 侧的 @Native()
      // 不需要显式写 assetId，默认就能找到这个动态库。
      assetName: 'pigeon_core.dart',
      // 逐文件列出，不用 glob：新增 C 文件时必须在这里登记，漏了会以
      // 「undefined symbol」的形式在链接期暴露，比运行时更难查的缺失要好。
      sources: <String>[
        'src/pigeon_core.c',
        'src/pc_common.c',
        'src/pc_http.c',
        'src/pc_authnet.c',
        'src/pc_bsphp.c',
        'src/pc_auth.c',
        'src/pc_cred.c',
        'src/pc_log.c',
      ],
      // 源码里有中文注释。不指定 /utf-8 时 MSVC 按系统代码页（简中机器上是
      // 936/GBK）解读源文件，会把 UTF-8 中文判成 warning C4819；万一以后
      // 写了宽字符串字面量还会被解错。/utf-8 = /source-charset:utf-8
      // + /execution-charset:utf-8。和 windows/CMakeLists.txt 里给 C++ 侧
      // 加的是同一个选项。
      flags: isWindows ? const <String>['/utf-8'] : const <String>[],
    );

    await library.build(
      input: input,
      output: output,
      // 让 PC_API 展开成 dllexport 而不是 dllimport。
      // 写成预处理器宏而不是在 .c 里 #define：符号是定义在同一个 DLL 里的，
      // 任何一个编译单元把声明当成 dllimport，链接期就会报找不到导入符号。
      defines: <String, String?>{'PIGEON_CORE_BUILD': '1'},
      // CLibrary.build 的默认值会随构建模式变：
      //   link hook 可用时 → routing 到 link hook + 静态库（供 LTO/裁剪符号）
      //   否则            → 直接进应用包 + 动态库
      // 本包没有 hook/link.dart（也不需要：核心函数不多，不值得引入
      // record_use 符号映射那套机器），所以必须显式固定成「动态库 + 直接进
      // 应用包」。否则 release 构建会因为「静态资产被送去 link hook，但本包
      // 没有 link hook」而直接失败。
      routing: const <AssetRouting>[ToAppBundle()],
      linkModePreference: LinkModePreference.dynamic,
    );
  });
}
