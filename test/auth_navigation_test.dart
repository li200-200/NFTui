// ---------------------------------------------------------------------------
// 页面切换：验证页 → 注册 / 充值 → 回登录，以及协议页弹出
//
// 【为什么用 widget 测试而不是实机点击】
// 这条链路的正确性只取决于「点某个链接后回调有没有发出去」，与窗口尺寸切换
// 无关。而实机点击要处理窗口被遮挡、鼠标事件被 UIPI 吞掉、DPI 换算这些与
// 业务无关的干扰 —— 用 widget 测试盯业务，实机只用于看「长得对不对」。
//
// 【登录成功的分支不在这里测】
// 它要发真实网络请求（pcAuthLogin 走 Isolate.run），测试里等不到结果；
// 而且紧接着要调 window_manager 改窗口尺寸，测试环境没有原生插件会抛异常。
// 那一段的正确性靠 C 侧的表单校验测试（packages/pigeon_core/test）+ 实机验证。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_ui/pages/login_page.dart';
import 'package:app_ui/pages/recharge_page.dart';
import 'package:app_ui/pages/register_page.dart';
import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/illustration_panel.dart';

void main() {
  setUp(() {
    // 花瓣是无限循环动画，会让 pumpAndSettle 永不收敛。
    IllustrationPanel.petalsEnabled = false;
  });

  /// 把页面装进 800x550 的表面。
  ///
  /// 【必须有 Scaffold】TextField 要求向上能找到 Material，否则抛
  /// 「No Material widget found」。生产代码里这层由 WindowShell 的 Material
  /// 提供；这里单独 pump 一个页面，得自己补上。
  Widget host(WidgetTester tester, Widget page) {
    tester.view.physicalSize = const Size(kAuthWidth, kAuthHeight);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: AuthColors.surface,
        body: SizedBox(
          width: kAuthWidth,
          height: kAuthHeight,
          child: page,
        ),
      ),
    );
  }

  testWidgets('点「注册账号」发出 onGoRegister', (WidgetTester tester) async {
    bool went = false;
    await tester.pumpWidget(
      host(
        tester,
        LoginPage(
          onGoRegister: () => went = true,
          onGoRecharge: () {},
          onLoginSuccess: (_) {},
          credPath: '',
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('注册账号'));
    await tester.pump();
    expect(went, isTrue);
  });

  testWidgets('点「充值」发出 onGoRecharge', (WidgetTester tester) async {
    bool went = false;
    await tester.pumpWidget(
      host(
        tester,
        LoginPage(
          onGoRegister: () {},
          onGoRecharge: () => went = true,
          onLoginSuccess: (_) {},
          credPath: '',
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('充值'));
    await tester.pump();
    expect(went, isTrue);
  });

  testWidgets('注册页点返回发出 onBack', (WidgetTester tester) async {
    bool went = false;
    await tester.pumpWidget(
      host(
        tester,
        RegisterPage(
          onBack: () => went = true,
          onRegisterSuccess: (_) {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    expect(went, isTrue);
  });

  testWidgets('充值页预填登录页带过来的账号', (WidgetTester tester) async {
    await tester.pumpWidget(
      host(
        tester,
        RechargePage(
          onBack: () {},
          initialUser: 'abc123',
          onSubmitSuccess: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('abc123'), findsOneWidget);
  });

  testWidgets('协议页能从页脚链接打开', (WidgetTester tester) async {
    await tester.pumpWidget(
      host(
        tester,
        LoginPage(
          onGoRegister: () {},
          onGoRecharge: () {},
          onLoginSuccess: (_) {},
          credPath: '',
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('软件使用协议'));
    await tester.pumpAndSettle();

    // 协议正文第一段的标题
    expect(find.text('一、总则'), findsOneWidget,
        reason: '点页脚链接应弹出协议页');
  });
}
