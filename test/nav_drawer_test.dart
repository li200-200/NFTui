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
import 'package:app_ui/widgets/setting_table.dart';
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

    // 设置：三个分组来自 config.ui，逐项核对标题与控件文案。
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsWidgets);
    expect(find.text('小号区'), findsOneWidget);
    expect(find.text('滑块区'), findsOneWidget);
    expect(find.text('上号器区'), findsOneWidget);
    // 小号表的列头。必须限定在抽屉内 —— 右侧主表格也有 no / phone / token
    // 这几个列名，不限定范围会一次找到两处。
    final Finder inDrawer = find.descendant(
      of: find.byType(SettingsPanel),
      matching: find.byType(Text),
    );
    for (final String col in <String>['no', 'phone', 'token']) {
      expect(
        find.descendant(
          of: find.byType(SubAccountTable),
          matching: find.text(col),
        ),
        findsOneWidget,
        reason: '小号表应有「$col」列',
      );
    }
    // 四个开关 + 四个按钮（最新 .ui 新增了代理区与通知区）。
    // 需求指定「选择框使用开关样式」，文案照抄 .ui：
    // 启用小号 / 启用滑块 / 启用代理 ×2（checkBox_qydl 与 checkBox_qydl_2 同名）。
    expect(find.byType(SwitchTrack), findsNWidgets(4));
    expect(find.text('启用小号'), findsOneWidget);
    expect(find.text('启用滑块'), findsOneWidget);
    expect(find.text('启用代理'), findsNWidgets(2));
    expect(find.text('获取'), findsOneWidget);
    // 「链接」三个：滑块区 pushButton_hklj、上号器区 pushButton_shqlj、
    // 代理区 pushButton_dllj。
    expect(find.text('链接'), findsNWidgets(3));
    // 上号器区的「断开」与通知区的「测试」。
    expect(find.text('断开'), findsOneWidget);
    expect(find.text('测试'), findsOneWidget);
    // 上号器区的前缀输入框 + 两行 `*` 提示（代理区的 label_dl 与滑块区同文案）。
    // 最新 .ui 把格式说明并进了分组标题、删掉了那个输入框，所以标题里能看到它。
    expect(find.text('前缀'), findsOneWidget);
    expect(find.text('格式：前缀-手机号-密码-支付密码'), findsOneWidget);
    expect(find.text('*使用工具先获取小号数据'), findsOneWidget);
    expect(find.text('*滑块需要配合使用工具'), findsNWidgets(2));
    // 新增的两个分区标题。
    expect(find.text('代理区'), findsOneWidget);
    expect(find.text('通知区'), findsOneWidget);
    expect(inDrawer, findsWidgets); // 确保 finder 有效

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

  testWidgets('三个抽屉的宽度各不相同：按各自内容量定档', (WidgetTester tester) async {
    setSurface(tester, kDesignWidth, kDesignHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    /// 抽屉盒（含边框与内边距）的宽度。
    double drawerBoxWidth() => tester
        .getRect(
          find
              .descendant(
                of: find.byType(SlideOutDrawer),
                matching: find.byType(Container),
              )
              .first,
        )
        .width;

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    final double settingsW = drawerBoxWidth();

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    final double profileW = drawerBoxWidth();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    final double menuW = drawerBoxWidth();

    // ignore: avoid_print
    print('抽屉宽度: 设置 $settingsW / 个人中心 $profileW / 菜单 $menuW');

    // 设置页要放五张卡片（通知区一行四件控件），是三档里最宽的。
    expect(settingsW, kDrawerWidthSettings);
    expect(profileW, kDrawerWidthProfile);
    expect(menuW, kDrawerWidthMenu);

    // 需求：个人中心与菜单的抽屉要窄一些。
    expect(profileW, lessThan(settingsW));
    expect(menuW, lessThan(settingsW));
    // 菜单内容最少（四个短条目），应是最窄的。
    expect(menuW, lessThan(profileW));
  });

  testWidgets('窄抽屉下个人中心与菜单的内容仍完整、不溢出', (WidgetTester tester) async {
    setSurface(tester, kDesignWidth, kDesignHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // 个人中心：头像 + 账号 + 状态 + 按钮都要在 260 里放得下。
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '个人中心不该溢出');
    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('请先在左栏登录'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);

    // 菜单：四个条目在 200 里要能完整显示（「使用说明」四字约 50px）。
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '菜单不该溢出');
    for (final String s in <String>['使用说明', '运行日志', '检查更新', '关于']) {
      expect(find.text(s), findsOneWidget);
    }

    // 最窄档位下窗口再压小也不能溢出。
    setSurface(tester, kMinWidth, kMinHeight);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
