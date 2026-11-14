// ---------------------------------------------------------------------------
// 回归测试：曾经的真实 bug 与交互手感
//
// 【为什么单独一份文件】
// 这些用例守的不是「功能正常」，而是「这几个坑不要再踩回去」。每一条都对应
// 一个曾经实际发生过、且肉眼不容易发现的问题（回显卡死、遮罩硬编码、提示被
// 误删、零点几像素溢出、关闭动画缺失）。放在一起，改相关代码时一眼能看到
// 该保住什么。
// ---------------------------------------------------------------------------
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_ui/pages/main_page.dart';
import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/drawer_panels.dart';
import 'package:app_ui/widgets/nav_bar.dart';
import 'package:app_ui/widgets/panel_controls.dart';
import 'package:app_ui/widgets/task_table.dart';
import 'package:app_ui/widgets/work_snack.dart';

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

/// 抽屉的关闭按钮：标题栏也有一个 Icons.close，必须限定在抽屉内部找。
Finder drawerClose() => find.descendant(
  of: find.byType(SlideOutDrawer),
  matching: find.byIcon(Icons.close),
);

void main() {
  group('抽屉回显', () {
    testWidgets('开着抽屉改「并发」，设置面板的回显实时更新', (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      final LabeledField conc = tester
          .widgetList<LabeledField>(find.byType(LabeledField))
          .firstWhere((LabeledField f) => f.label == '并发');
      await tester.enterText(find.byWidget(conc), '42');
      await tester.pumpAndSettle();

      // 曾经：TextField 打字不触发页面 setState，回显永远停在打开时的值。
      final SettingsPanel panel = tester.widget<SettingsPanel>(
        find.byType(SettingsPanel),
      );
      expect(panel.concurrency, '42', reason: '回显应随输入实时更新');
    });

    testWidgets('开着抽屉填账号，个人中心认得出来', (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();
      expect(find.text('未登录'), findsOneWidget);

      final LabeledField acc = tester
          .widgetList<LabeledField>(find.byType(LabeledField))
          .firstWhere((LabeledField f) => f.label == '账户');
      await tester.enterText(find.byWidget(acc), '13800138000');
      await tester.pumpAndSettle();

      expect(
        tester.widget<ProfilePanel>(find.byType(ProfilePanel)).account,
        '13800138000',
      );
      expect(find.text('未登录'), findsNothing, reason: '填了账号就不该再显示未登录');
    });
  });

  group('左栏滚动条', () {
    testWidgets('放得下时不显示滚动条，放不下时才显示', (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      // 第一个 Scrollbar 是左栏的。
      // 曾经：thumbVisibility 硬开 true，1048x682 下明明不需要滚动却常驻一根，
      // 还把卡片挤窄 8px、左右内边距不对称。
      expect(
        tester.widgetList<Scrollbar>(find.byType(Scrollbar)).first.thumbVisibility,
        isFalse,
        reason: '设计尺寸下左栏放得下，不该显示滚动条',
      );

      tester.view.physicalSize = const Size(kMinWidth, kMinHeight);
      await tester.pumpAndSettle();

      expect(
        tester.widgetList<Scrollbar>(find.byType(Scrollbar)).first.thumbVisibility,
        isTrue,
        reason: '最小尺寸下左栏放不下，应显示滚动条',
      );
    });
  });

  group('极窄窗口', () {
    testWidgets('400 宽不溢出（标签条可横滚 + 状态列降级）', (WidgetTester tester) async {
      // 窗口最小宽是 880，这里故意压到 400 试抗压能力。
      // 曾经两处会爆：FlatTabBar 的 Row 溢出 66px、状态列的圆点+文字溢出 7.5px。
      setSurface(tester, 400, 600);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('极矮窗口 700x300 不溢出', (WidgetTester tester) async {
      setSurface(tester, 700, 300);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('提示条去重', () {
    testWidgets('同文案去重，但不误删不同文案', (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      final BuildContext ctx = tester.element(find.byType(MainPage));

      showWorkSnack(ctx, '消息B');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      showWorkSnack(ctx, '消息A');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      // 同文案再发一次：应当被跳过（既不新增也不清队列）。
      // 曾经这里调的是 clearSnackBars()，会把「消息B」一起抹掉。
      showWorkSnack(ctx, '消息A');
      await tester.pump();

      expect(
        find.text('消息B'),
        findsOneWidget,
        reason: '不同文案不该被同文案的去重逻辑误删',
      );
    });
  });

  group('抽屉进出动画', () {
    testWidgets('关闭时播退场动画，不是瞬间消失', (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.byType(SlideOutDrawer), findsOneWidget);

      await tester.tap(drawerClose());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      // 退场中途抽屉应当还在（正往右滑出去）。
      expect(
        find.byType(SlideOutDrawer),
        findsOneWidget,
        reason: '关闭应有过渡，不能瞬间移除',
      );

      await tester.pumpAndSettle();
      expect(find.byType(SlideOutDrawer), findsNothing);
    });

    testWidgets('关闭后遮罩不挡点击', (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(drawerClose());
      await tester.pumpAndSettle();

      // 遮罩常驻在树里（为了播淡出），收起后必须不拦截点击 ——
      // 否则表格的右键菜单会被一层透明的 GestureDetector 吃掉。
      final TestGesture g = await tester.startGesture(
        tester.getCenter(
          find.descendant(
            of: find.byType(TaskTable).first,
            matching: find.text('13800138000'),
          ),
        ),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await g.up();
      await tester.pumpAndSettle();

      expect(find.text('全选'), findsOneWidget, reason: '表格右键菜单应能正常弹出');
    });
  });

  group('遮罩浓度', () {
    testWidgets('取的是 theme 里的 kDrawerScrimAlpha，不是硬编码', (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // 找到遮罩那一层 ColoredBox（抽屉内部没有 ColoredBox，标题栏用的是
      // Container，所以这里只会命中遮罩）。
      final Iterable<ColoredBox> boxes = tester.widgetList<ColoredBox>(
        find.byType(ColoredBox),
      );
      final ColoredBox scrim = boxes.firstWhere(
        (ColoredBox b) => b.color.a > 0 && b.color.a < 1,
        orElse: () => throw StateError('没找到遮罩'),
      );
      // 曾经这里写死 Color(0x2E000000)，而 theme 里另有一个没人用的
      // kDrawerScrimAlpha —— 改常量毫无效果，注释却说已生效。
      expect(
        scrim.color.a,
        closeTo(kDrawerScrimAlpha, 0.01),
        reason: '遮罩透明度应来自 kDrawerScrimAlpha',
      );
    });
  });
}
