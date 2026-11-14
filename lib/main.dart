// ---------------------------------------------------------------------------
// 入口
//
// 窗口 1048x682（取自 .ui 的 geometry），最小 880x620。
// 尺寸真正的来源是原生层 windows/runner/main.cpp 里的 kWindowWidth/kWindowHeight，
// 这里再设一遍是为了：
//   · 保证 Dart 侧拿到的约束一致；
//   · 把最小尺寸锁死，避免拖小之后左栏卡片被压扁。
//
// 窗口没有系统标题栏（原生层用 WS_POPUP，Dart 侧用 TitleBarStyle.hidden），
// 标题与最小化 / 关闭都由 WorkTitleBar 自绘。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'package:app_ui/pages/main_page.dart';
import 'package:app_ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 先 runApp 再补窗口设置：Dart 侧首帧干等一串原生通道，而这些调用没有一个是
  // 首帧内容需要的 —— 原生层已经按设计尺寸创建并居中过窗口了，下面只是把
  // 「最小尺寸」这类约束补齐。
  runApp(const AppUi());

  await _setupWindow();
}

Future<void> _setupWindow() async {
  /* 【原生通道可能不可用】window_manager 的原生插件在注册失败（插件未打包、
   * 平台不支持、或被加载器拦下）时，ensureInitialized() 会抛异常。这里降级成
   * 「设置失败也继续」，至少界面能出来 —— 否则异常进到 main() 的 Zone，
   * 后续 waitUntilReadyToShow 根本不会执行，窗口永远不显示。 */
  try {
    await windowManager.ensureInitialized();
  } on Object catch (e) {
    debugPrint('窗口管理器初始化失败，跳过窗口设置：$e');
    return;
  }

  const WindowOptions options = WindowOptions(
    size: Size(kDesignWidth, kDesignHeight),
    minimumSize: Size(kMinWidth, kMinHeight),
    center: true,
    /* 【为什么这里是 normal 而不是 hidden】
     *
     * window_manager 在 TitleBarStyle.hidden 下会在自己的 WM_NCCALCSIZE 里把
     * 客户区左右各缩 8px、底部再缩 8px（见插件源码 adjustNCCALCSIZE 之后的
     * sz->rgrc[0].right -= 8 那几行）。它的窗口过程优先级高于 runner 里的
     * Win32Window::MessageHandler，所以 1048x682 的窗口拿到 Dart 侧只剩
     * 1032x674 —— 四周露出一圈桌面，看上去像界面没铺满。
     *
     * 无边框这件事改由 runner 自己做（windows/runner/win32_window.cpp 的
     * WS_POPUP + WM_NCCALCSIZE 返回 0 + WM_NCHITTEST 补回热区），
     * 这里就不再让插件插手，客户区与窗口严丝合缝。
     *
     * titleBarStyle: normal 在 WS_POPUP 下并不会画出系统标题栏 ——
     * 那个样式位在创建窗口时就没了，插件只是「不去改」而已。 */
    titleBarStyle: TitleBarStyle.normal,
    title: kWindowTitle,
    skipTaskbar: false,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    /* 【首帧等待必须有超时兜底】
     *
     * waitUntilFirstFrameRasterized 在「首帧永远不会产生」的情况下永不完结
     * （GPU / 光栅化上下文创建失败、引擎初始化异常等），回调因此卡死、show()
     * 永远不被调用：进程活着、任务管理器里有它，但屏幕上没有窗口。
     *
     * 这里用 3 秒超时竞争：先到者赢。超时也照样 show —— 宁可让用户看到一帧
     * 空白再重绘，也不要给出一个没有窗口的僵尸进程。 */
    await Future.any(<Future<void>>[
      WidgetsBinding.instance.waitUntilFirstFrameRasterized,
      Future<void>.delayed(const Duration(seconds: 3)),
    ]);
    await windowManager.show();
    await windowManager.focus();
  });
}

class AppUi extends StatelessWidget {
  const AppUi({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kWindowTitle,
      debugShowCheckedModeBanner: false,
      // 输入框右键菜单的「剪切 / 复制 / 粘贴 / 全选」文案由 MaterialLocalizations
      // 提供，默认是美式英语。把语言定成中文之后框架自己给出中文词条。
      locale: const Locale('zh'),
      supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(),
      // 整窗铺满底色：不做窗口级透明 / 亚克力合成，Dart 侧自己画满每一像素，
      // 首帧前后表现才可预期。
      builder: (BuildContext context, Widget? child) {
        return ColoredBox(
          color: AppColors.surface,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const MainPage(),
    );
  }
}
