// ---------------------------------------------------------------------------
// 底部图标条 + 右侧抽屉
//
// 【这份测试守的是什么】
// 抽屉最容易被后续改动破坏的地方是「覆盖范围」——它必须只盖右侧工作区，
// 左栏在抽屉打开期间要仍然可读可点。这条不是靠肉眼能长期守住的：
// 有人把 Stack 提到整页外面、或者改用 Scaffold.endDrawer，几何断言会立刻报错。
//
// 其次是「同一项再点收起 / 点另一项切换」这个状态机 —— 它只有三种转移，
// 但写成 if 嵌套时很容易漏掉一种。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_ui/pages/main_page.dart';
import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/drawer_panels.dart';
import 'package:app_ui/widgets/nav_bar.dart';
import 'package:app_ui/widgets/panel_controls.dart';
import 'package:app_ui/widgets/task_table.dart';

Widget wrap() => MaterialApp(
  locale: const Locale('zh'),
  supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
  localizationsDelegates: const <LocalizationsDelegate<Object>>[
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: buildAppTheme(),
  home: const MainPage(),
);

void setSurface(WidgetTester tester, double w, double h) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(w, h);
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('底部三个图标齐备，且整条不侵入右侧表格', (WidgetTester tester) async {
    setSurface(tester, kDesignWidth, kDesignHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.byType(NavBar), findsOneWidget);
    // 三个图标各自一枚（未选中态）。
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsOneWidget);

    final Rect nav = tester.getRect(find.byType(NavBar));
    final Rect table = tester.getRect(find.byType(TaskTable).first);
    expect(
      nav.right,
      lessThanOrEqualTo(table.left),
      reason: '图标条属于左栏，不应伸到表格上（nav=$nav table=$table）',
    );

    // 图标条贴底：底边与表格底边齐平（同一行 Row 的两个子项）。
    expect(nav.bottom, closeTo(table.bottom, 0.5));
  });

  testWidgets('抽屉从右滑出，宽度固定，且左边界在左栏之外', (WidgetTester tester) async {
    setSurface(tester, kDesignWidth, kDesignHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.byType(SlideOutDrawer), findsNothing, reason: '初始不应有抽屉');

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump(); // 插入树
    await tester.pump(const Duration(milliseconds: 100));

    // 中途：已经可见，但还没滑到位。
    final Rect mid = tester.getRect(find.byType(SettingsPanel));

    await tester.pumpAndSettle();
    final Rect done = tester.getRect(find.byType(SettingsPanel));

    expect(mid.left, greaterThan(done.left), reason: '抽屉应从右向左滑入');
    // 单帧位移不得超过抽屉宽度 —— 否则说明位移作用在了满宽的盒子上，
    // 前一段行程会跑到屏幕外空跑（曾经踩过这个坑）。
    expect(
      mid.left - done.left,
      lessThan(kDrawerWidth),
      reason: '滑入距离应等于抽屉宽度，不是整个右栏宽度',
    );

    // 抽屉盒（含边框与内边距）宽度固定。
    final Rect box = tester.getRect(
      find
          .descendant(
            of: find.byType(SlideOutDrawer),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(box.width, kDrawerWidth);

    // 关键断言：不覆盖左栏。
    final Rect nav = tester.getRect(find.byType(NavBar));
    expect(
      box.left,
      greaterThan(nav.right),
      reason: '抽屉左边界必须在左栏右边界之右（左栏 ${nav.right} / 抽屉 ${box.left}）',
    );
    // 右侧贴住工作区右边缘，不留缝。
    final Rect table = tester.getRect(find.byType(TaskTable).first);
    expect(box.right, closeTo(table.right, 0.5));
  });

  testWidgets('图标状态机：同项收起、异项切换', (WidgetTester tester) async {
    setSurface(tester, kDesignWidth, kDesignHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // 开设置。
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPanel), findsOneWidget);

    // 异项切换 → 个人中心。
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPanel), findsNothing);
    expect(find.byType(ProfilePanel), findsOneWidget);

    // 异项切换 → 菜单。选中态图标换成 menu_open。
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.byType(ProfilePanel), findsNothing);
    expect(find.byType(MenuPanel), findsOneWidget);
    expect(find.byIcon(Icons.menu_open), findsOneWidget, reason: '选中时用实心图标');
    expect(find.byIcon(Icons.menu), findsNothing);

    // 同项再点 → 收起，图标回到未选中态。
    await tester.tap(find.byIcon(Icons.menu_open));
    await tester.pumpAndSettle();
    expect(find.byType(SlideOutDrawer), findsNothing);
    expect(find.byIcon(Icons.menu), findsOneWidget);
  });

  testWidgets('点遮罩空白收起抽屉', (WidgetTester tester) async {
    setSurface(tester, kDesignWidth, kDesignHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.byType(SlideOutDrawer), findsOneWidget);

    // 点表格左侧（遮罩上、抽屉外）。
    final Rect table = tester.getRect(find.byType(TaskTable).first);
    await tester.tapAt(Offset(table.left + 40, table.center.dy));
    await tester.pumpAndSettle();
    expect(find.byType(SlideOutDrawer), findsNothing);
  });

  testWidgets('抽屉打开时左栏仍可交互（遮罩不覆盖左栏）', (WidgetTester tester) async {
    setSurface(tester, kDesignWidth, kDesignHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    // 「开始」可点 → 点完变禁用（说明左栏收到点击且状态生效）。
    final PanelButton before = tester.widget<PanelButton>(
      find.widgetWithText(PanelButton, '开始'),
    );
    expect(before.onPressed, isNotNull);

    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();

    final PanelButton after = tester.widget<PanelButton>(
      find.widgetWithText(PanelButton, '开始'),
    );
    expect(after.onPressed, isNull, reason: '左栏按钮应真的收到点击');
    expect(
      find.byType(SlideOutDrawer),
      findsOneWidget,
      reason: '点左栏不应把抽屉关掉',
    );
  });

  testWidgets('抽屉内容：三个面板的关键文案都在', (WidgetTester tester) async {
    setSurface(tester, kDesignWidth, kDesignHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // 设置。
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsWidgets);
    expect(find.text('开机自动启动'), findsOneWidget);
    expect(find.text('失败自动重试'), findsOneWidget);
    expect(find.text('操作完成时提示'), findsOneWidget);

    // 个人中心：未登录时按钮禁用。
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('未登录'), findsOneWidget);
    final PanelButton logout = tester.widget<PanelButton>(
      find.widgetWithText(PanelButton, '退出登录'),
    );
    expect(logout.onPressed, isNull, reason: '未登录时「退出登录」应禁用');

    // 菜单：四项齐全且顺序固定。
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    const List<String> expected = <String>['使用说明', '运行日志', '检查更新', '关于'];
    final List<double> tops = <double>[
      for (final String s in expected) tester.getTopLeft(find.text(s)).dy,
    ];
    expect(tops, orderedEquals(<double>[...tops]..sort()));
  });
}
