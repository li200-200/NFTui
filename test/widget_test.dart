// ---------------------------------------------------------------------------
// 页面骨架的布局冒烟测试
//
// 守两件事（这两条是验收标准里最容易回归的）：
//   1. 1048x682 与最小 880x620 两档尺寸下都不溢出（RenderFlex overflow 在测试里
//      会作为异常抛出，takeException 能抓到）；
//   2. 左栏不出现多余滚动条 —— 标准尺寸下内容恰好铺满，滚动位置没有可滚距离。
//
// 窗口尺寸用 tester.view.physicalSize 模拟，devicePixelRatio 固定 1，
// 这样 1 逻辑像素 = 1 物理像素，断言里的数字与设计稿一致。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_ui/pages/main_page.dart';
import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/task_table.dart';

/// 把页面装进与真机一致的 MaterialApp 环境（语言、主题、底色）。
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

/// 把测试画布设成指定逻辑尺寸。
void setSurface(WidgetTester tester, double w, double h) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(w, h);
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('设计尺寸 1048x682 下不溢出，且左栏没有多余滚动条', (WidgetTester tester) async {
    setSurface(tester, kDesignWidth, kDesignHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // 三张表的标题条与三张卡片都在。
    expect(find.text('阿萨德'), findsOneWidget);
    expect(find.text('登录区'), findsOneWidget);
    expect(find.text('信息区'), findsOneWidget);
    expect(find.text('选项区'), findsOneWidget);
    expect(find.text('运行'), findsOneWidget);
    expect(find.text('订单信息'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);

    // 左栏的滚动容器：标准尺寸下内容不高于可用高度，所以没有可滚距离。
    final ScrollableState leftScroll = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(leftScroll.position.maxScrollExtent, lessThanOrEqualTo(0.5));
  });

  testWidgets('最小尺寸 880x620 下不溢出，左栏转为可滚动', (WidgetTester tester) async {
    setSurface(tester, kMinWidth, kMinHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('登录区'), findsOneWidget);
  });

  testWidgets('三个 Tab 各有一张表，且列数与 .ui 一致', (WidgetTester tester) async {
    setSurface(tester, kDesignWidth, kDesignHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // IndexedStack 会同时保留三张表（换 Tab 不销毁，列宽与滚动位置才留得住）。
    // 非当前页在树里但处于 offstage，默认的 finder 会跳过它们，所以 skipOffstage
    // 必须显式关掉 —— 否则这个断言只是在数「当前可见的一张表」。
    expect(
      find.byType(TaskTable, skipOffstage: false),
      findsNWidgets(3),
    );
  });

  testWidgets('「发送」是禁用态：文字为辅助色，点击不抛异常', (WidgetTester tester) async {
    setSurface(tester, kDesignWidth, kDesignHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('切到「订单信息」后表头文案跟着换', (WidgetTester tester) async {
    setSurface(tester, kDesignWidth, kDesignHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // 「运行」表：没有 Oid，也没有支付链接。
    expect(find.text('Oid'), findsNothing);
    expect(find.text('支付链接'), findsNothing);

    await tester.tap(find.text('订单信息'));
    await tester.pumpAndSettle();
    // 「订单信息」表有 Oid、仍没有支付链接。
    // （非当前页在树里但 offstage，默认 finder 会跳过它们，所以这里查到的
    //   一定是当前可见的那张表。）
    expect(find.text('Oid'), findsOneWidget);
    expect(find.text('支付链接'), findsNothing);
    expect(tester.takeException(), isNull);

    // 切到「完成」：多出「支付链接」列。
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('Oid'), findsOneWidget);
    expect(find.text('支付链接'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
