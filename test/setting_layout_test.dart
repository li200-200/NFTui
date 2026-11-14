// ---------------------------------------------------------------------------
// 设置页的布置测试：控件尺寸、对齐、留白
//
// 这份测试取代了上一版的「与 config.ui 逐像素比对」。需求已经从「位置必须
// 一模一样」改成了「布置要优化」，所以断言的对象也换了：
//   · 输入框与左栏登录区同高（30）、同组件；
//   · 卡片标题用 SectionLabel；
//   · no 列窄、phone/token 宽；
//   · 卡片铺满抽屉、左边界对齐、间距一致。
//
// 【为什么仍然单独一份文件】
// 这些断言都在量几何关系，与 settings_test 里「控件在不在、点了有没有反应」
// 是两类问题。混在一起时，一条几何断言失败会淹没在一堆交互用例的日志里。
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

Future<void> openSettings(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(kDesignWidth, kDesignHeight);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(wrap());
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle();
}

/// 取某个标题对应的卡片矩形。
Rect cardOf(WidgetTester tester, String title) => tester.getRect(
  find
      .ancestor(of: find.text(title), matching: find.byType(PanelGroupBox))
      .first,
);

void main() {
  testWidgets('三张卡片铺满抽屉内容区（右侧不留空白）', (WidgetTester tester) async {
    await openSettings(tester);

    // 【为什么量 SettingsPanel 而不是 SlideOutDrawer】
    // SlideOutDrawer 外面套着一层 Align，它的矩形是「整个右栏」，不是抽屉盒。
    // SettingsPanel 是抽屉内容区的直接子项，它的矩形就是可用宽度（扣掉抽屉
    // 左边框与内边距），卡片应当正好填满它。
    final Rect content = tester.getRect(find.byType(SettingsPanel));
    final Rect drawerBox = tester.getRect(
      find
          .descendant(
            of: find.byType(SlideOutDrawer),
            matching: find.byType(Container),
          )
          .first,
    );

    for (final String title in <String>['小号区', '滑块区', '上号器区']) {
      final Rect card = cardOf(tester, title);
      // ignore: avoid_print
      print('$title: 卡片 ${card.left}..${card.right} / '
          '内容区 ${content.left}..${content.right} / '
          '抽屉盒 ${drawerBox.left}..${drawerBox.right}');

      expect(
        card.left,
        closeTo(content.left, 1.0),
        reason: '$title 的左边界应贴住内容区左边',
      );
      expect(
        card.right,
        closeTo(content.right, 1.0),
        reason: '$title 的右边界应贴住内容区右边（上一版会差约 49px）',
      );
      // 卡片右边界与抽屉盒右边界之间只剩内边距。
      expect(
        drawerBox.right - card.right,
        closeTo(kDrawerContentPadding.right, 1.5),
      );
    }
  });

  testWidgets('三张卡片宽度一致、左边界对齐', (WidgetTester tester) async {
    await openSettings(tester);

    final List<Rect> cards = <Rect>[
      for (final String t in <String>['小号区', '滑块区', '上号器区'])
        cardOf(tester, t),
    ];
    for (final Rect r in cards) {
      expect(r.left, closeTo(cards.first.left, 0.5));
      expect(r.width, closeTo(cards.first.width, 0.5));
    }
  });

  testWidgets('卡片间距等于 kSettingCardGap，不再是 0~2px', (WidgetTester tester) async {
    await openSettings(tester);

    final Rect sub = cardOf(tester, '小号区');
    final Rect slider = cardOf(tester, '滑块区');
    final Rect loader = cardOf(tester, '上号器区');

    expect(slider.top - sub.bottom, closeTo(kSettingCardGap, 1.0));
    expect(loader.top - slider.bottom, closeTo(kSettingCardGap, 1.0));
  });

  testWidgets('小号表 no 列窄、phone 与 token 分走剩余宽度', (WidgetTester tester) async {
    await openSettings(tester);

    // 表头单元格的文字位置反映列宽：量每列文字到下一列文字的间隔。
    final Rect noHeader = tester.getRect(
      find
          .descendant(
            of: find.byType(SubAccountTable),
            matching: find.text('no'),
          )
          .first,
    );
    final Rect phoneHeader = tester.getRect(
      find
          .descendant(
            of: find.byType(SubAccountTable),
            matching: find.text('phone'),
          )
          .first,
    );
    final Rect tokenHeader = tester.getRect(
      find
          .descendant(
            of: find.byType(SubAccountTable),
            matching: find.text('token'),
          )
          .first,
    );

    final double noCol = phoneHeader.left - noHeader.left;
    final double phoneCol = tokenHeader.left - phoneHeader.left;

    // ignore: avoid_print
    print('列宽: no=$noCol phone=$phoneCol');

    // no 列固定 34；三列等分时它会是 104。
    expect(noCol, closeTo(kSettingTableNoWidth, 1.5));
    expect(noCol, lessThan(50));
    // phone 列拿到剩余宽度的一半，比 no 列宽得多（11 位手机号要 77px）。
    expect(phoneCol, greaterThan(noCol * 2));
  });

  testWidgets('设置页输入框与登录区输入框同高、同组件', (WidgetTester tester) async {
    await openSettings(tester);

    final List<LabeledField> fields = tester
        .widgetList<LabeledField>(find.byType(LabeledField))
        .toList();

    final LabeledField account = fields.firstWhere(
      (LabeledField f) => f.label == '账户',
    );
    final LabeledField prefix = fields.firstWhere(
      (LabeledField f) => f.label == '前缀',
    );

    final Rect accountRect = tester.getRect(find.byWidget(account));
    final Rect prefixRect = tester.getRect(find.byWidget(prefix));

    // 两处输入框同一行高 —— 上一版设置页的输入框是 20 高，比登录区矮 10px。
    expect(accountRect.height, kRowHeight);
    expect(prefixRect.height, kRowHeight);

    // 标签格宽度不同是刻意的：上号器区一行要塞四件，前缀的标签格收到 44
    // （见 kSettingLoaderLabelWidth 的推导）；登录区仍是 60。
    expect(account.labelWidth, kLabelWidth);
    expect(prefix.labelWidth, kSettingLoaderLabelWidth);
    expect(prefix.labelWidth, lessThan(account.labelWidth));
  });

  testWidgets('卡片标题用 SectionLabel（与登录区同款）', (WidgetTester tester) async {
    await openSettings(tester);

    for (final String title in <String>['小号区', '滑块区', '上号器区']) {
      final Finder box = find
          .ancestor(of: find.text(title), matching: find.byType(PanelGroupBox))
          .first;
      expect(
        find.descendant(of: box, matching: find.byType(SectionLabel)),
        findsOneWidget,
        reason: '$title 的标题应是 SectionLabel',
      );
    }

    // 左栏四张卡片也用同一个组件，样式自然一致。
    final Finder loginBox = find
        .ancestor(of: find.text('登录区'), matching: find.byType(PanelGroupBox))
        .first;
    expect(
      find.descendant(of: loginBox, matching: find.byType(SectionLabel)),
      findsOneWidget,
    );
  });

  testWidgets('开关、按钮、提示在同一行（纵向中心对齐）', (WidgetTester tester) async {
    await openSettings(tester);

    /// 取某张卡片里三个控件的矩形。提示可能不存在（上号器区就没有）。
    ({Rect sw, Rect btn, Rect? tip}) rowOf(String title) {
      final Finder box = find
          .ancestor(of: find.text(title), matching: find.byType(PanelGroupBox))
          .first;
      final Finder tipFinder = find.descendant(
        of: box,
        matching: find.byType(SettingTip),
      );
      return (
        sw: tester.getRect(
          find.descendant(of: box, matching: find.byType(SwitchRow)).first,
        ),
        btn: tester.getRect(
          find.descendant(of: box, matching: find.byType(PanelButton)).first,
        ),
        tip: tipFinder.evaluate().isEmpty
            ? null
            : tester.getRect(tipFinder.first),
      );
    }

    // 小号区与滑块区都有提示，三件必须同排。
    for (final String title in <String>['小号区', '滑块区']) {
      final r = rowOf(title);
      final Rect tip = r.tip!;
      // ignore: avoid_print
      print('$title: 开关 ${r.sw.center.dy.toStringAsFixed(1)} '
          '按钮 ${r.btn.center.dy.toStringAsFixed(1)} '
          '提示 ${tip.center.dy.toStringAsFixed(1)}');

      expect(
        r.btn.center.dy,
        closeTo(r.sw.center.dy, 1.5),
        reason: '$title 的按钮应与开关同排',
      );
      expect(
        tip.center.dy,
        closeTo(r.sw.center.dy, 1.5),
        reason: '$title 的提示应与开关同排（上一版提示单独占一行）',
      );
      // 顺序：开关在左、按钮居中、提示在右。
      expect(r.sw.right, lessThanOrEqualTo(r.btn.left));
      expect(r.btn.right, lessThanOrEqualTo(tip.left));
      // 提示不许折行撑高：单行高度不超过 kRowHeight。
      expect(tip.height, lessThanOrEqualTo(kRowHeight));
    }

    // 上号器区在最新 .ui 里已没有开关（末位换成了「断开」按钮），
    // 也不再是 _ActionRow 结构，单独一条测试覆盖，这里跳过。
  });

  testWidgets('上号器区：输入框、链接、断开在同一行', (WidgetTester tester) async {
    await openSettings(tester);

    final Finder box = find.byKey(const ValueKey<String>(kGroupBoxShq));

    final LabeledField prefix = tester
        .widgetList<LabeledField>(find.byType(LabeledField))
        .firstWhere((LabeledField f) => f.label == '前缀');

    final Rect field = tester.getRect(find.byWidget(prefix));
    final Rect link = tester.getRect(
      find.descendant(of: box, matching: find.text('链接')),
    );
    final Rect cut = tester.getRect(
      find.descendant(of: box, matching: find.text('断开')),
    );

    // ignore: avoid_print
    print('上号器区: 输入框 ${field.center.dy.toStringAsFixed(1)} '
        '链接 ${link.center.dy.toStringAsFixed(1)} '
        '断开 ${cut.center.dy.toStringAsFixed(1)}');

    // 三件纵向中心一致 —— 上一版输入框与按钮是上下两行。
    expect(link.center.dy, closeTo(field.center.dy, 1.5));
    expect(cut.center.dy, closeTo(field.center.dy, 1.5));

    // 顺序：输入框在左、链接居中、断开在右（与 .ui 的 x=50/140/220 一致）。
    expect(field.right, lessThanOrEqualTo(link.left));
    expect(link.right, lessThanOrEqualTo(cut.left));

    // 前缀输入框的标签格收窄到 44，把宽度让给输入框本身。
    expect(prefix.labelWidth, kSettingLoaderLabelWidth);
    // 输入框本体（扣掉 44 的标签格）仍要放得下「上号前缀」四个字的提示。
    expect(field.width - kSettingLoaderLabelWidth, greaterThan(60));

    // 这一区在最新 .ui 里已经没有勾选框了。
    expect(
      find.descendant(of: box, matching: find.byType(SwitchRow)),
      findsNothing,
    );
  });

  testWidgets('设置页三张卡片的高度足以容纳控件（不溢出）', (WidgetTester tester) async {
    await openSettings(tester);

    expect(tester.takeException(), isNull);

    // 小号区最高：表格（封顶 5 行）+ 间距 + 开关行 30 + 内边距。
    final Rect sub = cardOf(tester, '小号区');
    expect(
      sub.height,
      greaterThan(kSettingTableHeaderHeight +
          kSettingTableRowHeight * kSettingTableMaxRows),
    );
  });

  testWidgets('小号表：空数据显示 2 行，有数据最多 5 行', (WidgetTester tester) async {
    await openSettings(tester);

    double heightFor(int rows) =>
        kSettingTableHeaderHeight +
        kSettingTableRowHeight * rows +
        kSettingTableBorderWidth * 2;

    // 预置 10 条 → 封顶 5 行。
    final Rect full = tester.getRect(find.byType(SubAccountTable));
    // ignore: avoid_print
    print('10 条数据: 表格高 ${full.height}（5 行应为 ${heightFor(5)}）');
    expect(full.height, heightFor(kSettingTableMaxRows));

    // 5 行封顶：最后一条在视口外，框内可滚。
    expect(
      find.descendant(
        of: find.byType(SubAccountTable),
        matching: find.text('13000130009'),
      ),
      findsNothing,
      reason: '第 10 条应在滚动区外',
    );

    // 直接挂一个空表，验证「空数据显示 2 行」。
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: Center(
            child: SizedBox(width: 300, child: SubAccountTable(rows: [])),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Rect empty = tester.getRect(find.byType(SubAccountTable));
    // ignore: avoid_print
    print('空数据: 表格高 ${empty.height}（2 行应为 ${heightFor(2)}）');
    expect(empty.height, heightFor(kSettingTableMinRows));
    // 空表仍要能看出「这里是表格」，不是塌成一条表头。
    expect(empty.height, greaterThan(kSettingTableHeaderHeight));
    expect(find.text('暂无小号'), findsOneWidget);
  });

  testWidgets('小号表：数据不足 5 行时按实际行数收缩', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: SubAccountTable(
                rows: <SubAccount>[
                  SubAccount(no: '1', phone: '13800138000', token: 'tk_9f2a'),
                  SubAccount(no: '2', phone: '13900139001', token: 'tk_4b7c'),
                  SubAccount(no: '3', phone: '13700137002', token: 'tk_1c3d'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Rect three = tester.getRect(find.byType(SubAccountTable));
    final double want =
        kSettingTableHeaderHeight +
        kSettingTableRowHeight * 3 +
        kSettingTableBorderWidth * 2;
    // ignore: avoid_print
    print('3 条数据: 表格高 ${three.height}（3 行应为 $want）');
    expect(three.height, want);
    // 不足 5 行不需要滚动条。
    final Scrollbar bar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(bar.thumbVisibility, isFalse);
  });
}
