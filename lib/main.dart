// ---------------------------------------------------------------------------
// 入口
//
// 五个界面：登录 → 注册 / 充值 → 工作台，外加一个协议页（路由弹出）。
//
// 【两个窗口尺寸，不能混用】
//   · 验证页 800x550  —— 按参考图逐像素校对过（输入框 44 高、表单列 280、
//                        左右 40:60）；
//   · 工作台 1048x682 —— 取自 untitled.ui 的 geometry，左栏卡片加九列表格，
//                        800 宽会挤成一团。
// 登录成功时在同一个窗口里换页面并改窗口尺寸，见 [_AppState._enterWorkPage]。
//
// 尺寸真正的来源是原生层 windows/runner/main.cpp 里的 kWindowWidth/kWindowHeight
// （启动时按验证页尺寸创建并居中），Dart 侧再设一遍是为了：
//   · 保证 Dart 侧拿到的约束一致；
//   · 把最小 / 最大尺寸锁死，避免拖小之后布局被压扁。
//
// 窗口没有系统标题栏（原生层用 WS_POPUP，Dart 侧用 TitleBarStyle.hidden）：
// 验证页右上角只留「返回 / 关闭」两个圆钮，工作台用自绘标题条。
// ---------------------------------------------------------------------------
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pigeon_core/pigeon_core.dart';
import 'package:window_manager/window_manager.dart';

import 'package:app_ui/pages/login_page.dart';
import 'package:app_ui/pages/main_page.dart';
import 'package:app_ui/pages/recharge_page.dart';
import 'package:app_ui/pages/register_page.dart';
import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/window_chrome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 尽早安装崩溃处理器：崩溃/闪退时把异常信息写进 crash.log。
  pcCrashInstall();

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
    size: Size(kAuthWidth, kAuthHeight),
    // 需求：所有窗口大小不可改变（锁定最大尺寸，与最小一致）。
    // 启动时是验证页的 800x550，登录成功后由 _enterWorkPage 改成工作台尺寸。
    minimumSize: Size(kAuthWidth, kAuthHeight),
    maximumSize: Size(kAuthWidth, kAuthHeight),
    center: true,
    /* 【为什么这里是 normal 而不是 hidden】
     *
     * window_manager 在 TitleBarStyle.hidden 下会在自己的 WM_NCCALCSIZE 里把
     * 客户区左右各缩 8px、底部再缩 8px（见插件源码 adjustNCCALCSIZE 之后的
     * sz->rgrc[0].right -= 8 那几行）。它的窗口过程优先级高于 runner 里的
     * Win32Window::MessageHandler，所以 800x550 的窗口拿到 Dart 侧只剩
     * 784x542 —— 四周露出一圈桌面，看上去像界面没铺满。
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

/// 页面标识。
///
/// 整个应用只有这一个入口：`login` 是启动页，`work` 是登录后的工作台。
/// 工作台没有独立窗口、也没有独立可执行文件 —— 它只能由登录成功这条路径
/// 到达（见 [_AppState._enterWorkPage]），所以绕不过验证。
enum AppPage { login, register, recharge, work }

class AppUi extends StatefulWidget {
  const AppUi({super.key, this.credPath});

  /// 透传给登录页的「记住密码」存储路径。
  ///
  /// 测试传空串以隔离真实账号文件（空串 = 持久化完全禁用，见 pc_cred.h）。
  final String? credPath;

  @override
  State<AppUi> createState() => _AppState();
}

class _AppState extends State<AppUi> with WindowListener {
  AppPage _page = AppPage.login;

  /// 登录页 → 充值页 / 工作台要带过去，省得重输。
  String _userName = '';

  /// SnackBar 需要挂在 Scaffold 上，但本 State 的 context 位于 MaterialApp 之上，
  /// 用 of(context) 取不到。所以持有一个全局 key，由 MaterialApp 注入。
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // 拦截默认关闭，改由 onWindowClose 先清理后台线程再关闭。
    windowManager.setPreventClose(true);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // 1) 停心跳：避免退出瞬间还有心跳线程在发网络请求。
    pcHeartbeatStop();
    // 2) 确定性收尾并退出：停心跳 + 停日志刷新线程 + 释放日志控制台
    //    （conhost.exe 随之退出）+ 终止进程。不再依赖「窗口销毁 → 消息循环退出
    //    → main 返回」这条隐式链，杜绝进程/控制台残留。
    //    调用后进程立即结束，必须是最后一句。
    pcCoreShutdown(DateTime.now().millisecondsSinceEpoch);
  }

  void _go(AppPage page) {
    if (_page == page) return;
    setState(() => _page = page);
  }

  /// 验证通过：在同一个窗口里换成工作台，并把窗口切到工作台的尺寸。
  ///
  /// 两个尺寸都是有来由的，不能混用：
  ///   · 验证页 800x550 —— 按参考图逐像素校对过；
  ///   · 工作台 1048x682 —— 取自 untitled.ui 的 geometry。
  ///
  /// 【顺序很关键】先把最大尺寸放开再设新尺寸：启动时锁的是
  /// minimum == maximum == 800x550，直接 setSize(1048x682) 会被上限夹住，
  /// 窗口停在 800x550 而界面按 1048 布局，右下角直接被裁掉。
  Future<void> _enterWorkPage(String user) async {
    // 验证登录成功后，初始化运行日志控制台（不可关闭）。
    pcLogInit();
    // 日志可用之后立刻做一次 ABI 自检：C 结构体尺寸与 Dart 镜像不一致时
    // （改了某个 lens 宏却没同步另一侧），FFI 会按偏移读到错位数据，
    // 表现为「字符串后面粘着别的字段」「数字变成天文数字」，严重时越界崩。
    // 这里对一次，几十微秒，把隐性不一致变成日志里一条明确结论。
    pcAbiCheck();
    /* 获取系统公告并逐条输出到运行日志（api_type "1"）。
     *
     * 【为什么放在这里、为什么是 fire-and-forget】
     * 公告只是给用户看的提示信息，登录已经成功，它失败不该影响进工作台。
     * 但它是一次真实网络请求（最长 25s），同步等它会把窗口卡在那里 ——
     * 所以丢到后台 isolate，不 await。
     *
     * 【必须挂 catchError】这是个没有 await 的 Future，若公告接口异常
     * （断网 / 服务端返回异常），未处理的异步错误会冒到 Zone：debug 下直接
     * 变成红屏报错，release 下则静默丢失，排查时看不到任何线索。
     * catchError 的返回值要与 pcAuthNoticeAsync 的 Future<int> 类型一致。 */
    unawaited(pcAuthNoticeAsync().catchError((Object e) {
      debugPrint('获取公告失败：$e');
      return -1;
    }));

    setState(() {
      _userName = user;
      _page = AppPage.work;
    });

    // 需求：工作台窗口大小不可改变（最小=最大=设计尺寸，锁死）。
    // 放开上限 → 改尺寸 → 重新锁死 → 居中。
    await windowManager.setMaximumSize(
      const Size(kDesignWidth, kDesignHeight),
    );
    await windowManager.setMinimumSize(
      const Size(kDesignWidth, kDesignHeight),
    );
    await windowManager.setSize(const Size(kDesignWidth, kDesignHeight));
    await windowManager.center();
  }

  /// 退出登录：回到验证页，并把窗口收回验证页尺寸。
  ///
  /// 与 [_enterWorkPage] 对称，顺序反过来：先放开下限再改尺寸，否则
  /// setSize(800x550) 会被工作台的 1048x682 下限夹住。
  Future<void> _backToLogin() async {
    setState(() {
      _userName = '';
      _page = AppPage.login;
    });

    await windowManager.setMinimumSize(const Size(kAuthWidth, kAuthHeight));
    await windowManager.setMaximumSize(const Size(kAuthWidth, kAuthHeight));
    await windowManager.setSize(const Size(kAuthWidth, kAuthHeight));
    await windowManager.center();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kWindowTitle,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
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
      home: WindowShell(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (Widget child, Animation<double> anim) {
            return FadeTransition(opacity: anim, child: child);
          },
          child: KeyedSubtree(
            key: ValueKey<AppPage>(_page),
            child: _buildPage(),
          ),
        ),
      ),
    );
  }

  Widget _buildPage() {
    switch (_page) {
      case AppPage.login:
        return LoginPage(
          onGoRegister: () => _go(AppPage.register),
          onGoRecharge: () => _go(AppPage.recharge),
          onLoginSuccess: _enterWorkPage,
          credPath: widget.credPath,
        );

      case AppPage.register:
        return RegisterPage(
          onBack: () => _go(AppPage.login),
          onRegisterSuccess: (String user) {
            setState(() {
              _userName = user;
              _page = AppPage.login;
            });
            _toast('注册成功，请使用 $user 登录');
          },
        );

      case AppPage.recharge:
        return RechargePage(
          onBack: () => _go(AppPage.login),
          initialUser: _userName,
          onSubmitSuccess: (String user) {
            _toast('充值信息已提交');
          },
        );

      case AppPage.work:
        // 工作台自己持有全部业务状态；只有「验证登录」账号要传下去。
        return MainPage(
          loginAccount: _userName,
          onLogout: _backToLogin,
        );
    }
  }

  /// 轻量提示。放在底部居中，不打断操作。
  void _toast(String message) {
    final ScaffoldMessengerState? messenger = _messengerKey.currentState;
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontSize: 12.5,
            fontFamily: kFontFamily,
            fontFamilyFallback: kFontFallback,
          ),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        width: 300,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}
