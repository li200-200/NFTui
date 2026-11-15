// ---------------------------------------------------------------------------
// 工作台与验证页之间的接线
//
// 两件事在这里盯住：
//   1. 验证页登录成功后带过来的账号，会**预填**进工作台「登录区」的账户框；
//   2. 「退出登录」会发出 onLogout（由 main.dart 接过去切回验证页）。
//
// 【为什么只测这两条】
// 中间那段真实登录（pcAuthLogin → 网络 → _enterWorkPage）依赖网络和
// window_manager 的原生通道，widget 测试里跑不通 —— 它靠 C 侧的校验测试 +
// 实机验证覆盖。这里测的是「切过去之后数据对不对、能不能切回来」，
// 那部分是纯 Dart，稳定可测。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pigeon_core/pigeon_core.dart';

import 'package:app_ui/pages/main_page.dart';
import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/object_names.dart';

void main() {
  /// 按工作台的设计尺寸建表面。
  Widget host(Widget page) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: AppColors.surface,
        body: SizedBox(
          width: kDesignWidth,
          height: kDesignHeight,
          child: page,
        ),
      ),
    );
  }

  /// 读出「登录区」账户输入框里的文字。
  ///
  /// 用 objectName 常量定位（.ui 的 lineEdit_zh），与生产代码同一份契约。
  String accountText(WidgetTester tester) {
    final Finder field = find.descendant(
      of: find.byKey(const ValueKey<String>(kLineEditZh)),
      matching: find.byType(TextField),
    );
    return tester.widget<TextField>(field).controller!.text;
  }

  testWidgets('loginAccount 预填进「登录区」账户框', (WidgetTester tester) async {
    await tester.pumpWidget(host(const MainPage(loginAccount: 'abc123')));
    await tester.pump();

    expect(accountText(tester), 'abc123',
        reason: '验证页登录成功后，账号应预填到工作台的账户输入框');
  });

  testWidgets('loginAccount 为空时不预填，账户框保持空', (WidgetTester tester) async {
    await tester.pumpWidget(host(const MainPage()));
    await tester.pump();

    expect(accountText(tester), isEmpty);
  });

  testWidgets('预填之后用户仍能改账户（不是锁死的）', (WidgetTester tester) async {
    await tester.pumpWidget(host(const MainPage(loginAccount: 'abc123')));
    await tester.pump();

    final Finder field = find.descendant(
      of: find.byKey(const ValueKey<String>(kLineEditZh)),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'other999');
    await tester.pump();

    expect(accountText(tester), 'other999',
        reason: '工作台允许换另一个号，预填只是省一次输入');
  });

  testWidgets('点「退出登录」发出 onLogout', (WidgetTester tester) async {
    bool loggedOut = false;
    await tester.pumpWidget(
      host(
        MainPage(
          loginAccount: 'abc123',
          onLogout: () => loggedOut = true,
        ),
      ),
    );
    await tester.pump();

    // 打开个人中心抽屉
    await tester.tap(find.byTooltip('个人中心'));
    await tester.pumpAndSettle();

    // 「退出登录」按钮在抽屉里
    final Finder logout = find.text('退出登录');
    expect(logout, findsOneWidget, reason: '个人中心抽屉里应有退出登录按钮');

    await tester.tap(logout);
    await tester.pumpAndSettle();

    expect(loggedOut, isTrue,
        reason: '退出登录应通知上层切回验证页，而不是只清空输入框');
  });

  testWidgets('没有 onLogout 时退出登录只清空输入、不崩', (WidgetTester tester) async {
    await tester.pumpWidget(host(const MainPage(loginAccount: 'abc123')));
    await tester.pump();

    await tester.tap(find.byTooltip('个人中心'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();

    // 账户框被清空，抽屉收起
    expect(accountText(tester), isEmpty);
  });

  group('登录心跳', () {
    // 【这组测试会真的起 C 侧心跳线程】
    // MainPage.initState 里调 pcHeartbeatStart，dispose 里调 pcHeartbeatStop。
    // 这正是要验的东西：页面存活期 == 心跳存活期。所以不能用 mock，
    // 只能真的跑一遍再查 pcHeartbeatIsRunning。
    //
    // 【为什么要用 tester.runAsync】
    // testWidgets 默认跑在 FakeAsync 里：Future.delayed 不会真的等，时间由
    // tester.pump 手动推进；而 C 侧心跳线程是**真实的 OS 线程**，它的退出只跟
    // 真实时间有关。所以在 FakeAsync 里轮询 isRunning 会永远看到旧值，直到
    // 测试超时。runAsync 把这段代码放回真实事件循环，两边才对得上。

    /// 等心跳线程真的退干净。
    ///
    /// stop 是协作式的，且测试环境没有真实会话，心跳会走「TRANSIENT →
    /// 重新握手」分支（2 个网络请求，每个都可能等到连接超时）。所以上限给到
    /// 30 秒 —— 真正的 bug 是 running 永远不归零，那样 30 秒也过不了。
    Future<bool> waitHeartbeatStopped() async {
      for (int i = 0; i < 300; i++) {
        if (!pcHeartbeatIsRunning()) return true;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return false;
    }

    testWidgets('进工作台开启心跳，离开时停掉', (WidgetTester tester) async {
      /* 【不能假设起点是「未启动」】
       * flutter test 把所有测试文件跑在同一个进程里，前面任何一条 pump 过
       * MainPage 的测试都已经起过心跳，而且它的 dispose 可能还没收干净。
       * 所以这里先主动停一次，把状态拉回确定值 —— 顺带也验了 stop 的幂等性
       * （没在跑时调用不应报错）。 */
      final bool preStopped = await tester.runAsync(() async {
        pcHeartbeatStop();
        return waitHeartbeatStopped();
      }) ?? false;
      expect(preStopped, isTrue, reason: '前置条件：心跳应当能停干净');

      await tester.pumpWidget(host(const MainPage(loginAccount: 'abc123')));
      await tester.pump();

      expect(pcHeartbeatIsRunning(), isTrue,
          reason: '进入工作台 = 登录已成，必须开启心跳保活');

      // 换掉整棵树 → MainPage 被 dispose（内部调 pcHeartbeatStop）
      await tester.pumpWidget(host(const SizedBox.shrink()));
      await tester.pump();

      final bool stopped = await tester.runAsync(waitHeartbeatStopped) ?? false;
      expect(stopped, isTrue,
          reason: '离开工作台必须停掉心跳，否则服务端在线名额会被占着');
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
