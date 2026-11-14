// ---------------------------------------------------------------------------
// 设置页（抽屉里的「设置」）的测试
//
// 控件来源是 config.ui 的五个分组（小号区 / 滑块区 / 上号器区 / 代理区 / 通知区），
// 但**布局已按需求改成流式**（不再逐像素复刻 .ui 的绝对坐标）。所以这份测试守的是：
//   1. 控件齐全、分组归属正确、文案对得上 .ui；
//   2. 每个控件都能按 .ui 的 objectName 定位（Key 就是 objectName）；
//   3. 勾选框是开关样式（需求指定），且能切换；
//   4. 输入框与左栏登录区是同一个组件，卡片标题是同一个样式；
//   5. 卡片铺满抽屉内容区，右侧没有多余空白；
//   6. 代理区与通知区的所有控件都在同一行（需求指定）。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_ui/pages/main_page.dart';
import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/drawer_panels.dart';
import 'package:app_ui/widgets/panel_controls.dart';
import 'package:app_ui/widgets/setting_table.dart';
import 'package:app_ui/widgets/nav_bar.dart';

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

SettingsPanel panel(WidgetTester t) =>
    t.widget<SettingsPanel>(find.byType(SettingsPanel));

/// 小号表在显示 [rows] 行时的外框高度（表头 + 行 + 上下边框）。
double settingTableHeightFor(int rows) =>
    kSettingTableHeaderHeight +
    kSettingTableRowHeight * rows +
    kSettingTableBorderWidth * 2;

/// 按 .ui 的 objectName 找控件。
Finder byObjectName(String objectName) =>
    find.byKey(ValueKey<String>(objectName));

/// 打开设置抽屉。
Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle();
}

void main() {
  group('控件齐全', () {
    testWidgets('五个分组与 config.ui 对应', (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await openSettings(tester);

      // 五张卡片的标题（取自 .ui 的 groupBox title）。
      expect(find.text('小号区'), findsOneWidget);
      expect(find.text('滑块区'), findsOneWidget);
      expect(find.text('上号器区'), findsOneWidget);
      expect(find.text('代理区'), findsOneWidget);
      expect(find.text('通知区'), findsOneWidget);

      // 五张卡片的 objectName 都能定位到。
      for (final String name in <String>[
        kGroupBoxXhq,
        kGroupBoxHkq,
        kGroupBoxShq,
        kGroupBoxDl,
        kGroupBoxTz,
      ]) {
        expect(
          byObjectName(name),
          findsWidgets,
          reason: '$name 应当存在（kGroupBoxTz 与左栏操作区同名，故用 findsWidgets）',
        );
      }

      // 小号表列名取自 config.ui 的 column text。
      final SubAccountTable table = tester.widget<SubAccountTable>(
        byObjectName(kTableWidgetXh),
      );
      expect(table.columns, <String>['no', 'phone', 'token']);

      // 按钮文案（.ui 里的 pushButton_* text）：获取 1、链接 3、断开 1、测试 1。
      // 「链接」有三个：滑块区 pushButton_hklj、上号器区 pushButton_shqlj、
      // 代理区 pushButton_dllj。
      expect(find.text('获取'), findsOneWidget);
      expect(find.text('链接'), findsNWidgets(3));
      expect(find.text('断开'), findsOneWidget);
      expect(find.text('测试'), findsOneWidget);

      // 上号器区只剩「前缀」一个输入框（格式说明已并入标题）。
      final List<LabeledField> fields = tester
          .widgetList<LabeledField>(find.byType(LabeledField))
          .where((LabeledField f) => f.label == '前缀')
          .toList();
      expect(fields.length, 1);

      // 两行 `*` 提示照抄 .ui 的 label_xhts / label_hkts，代理区的 label_dl
      // 与滑块区文案相同（.ui 里就是复制过来的），所以出现两次。
      expect(find.text('*使用工具先获取小号数据'), findsOneWidget);
      expect(find.text('*滑块需要配合使用工具'), findsNWidgets(2));

      // 格式说明在「上号器区」的标题里（.ui 的 groupBox_shq.title）。
      expect(find.text('格式：前缀-手机号-密码-支付密码'), findsOneWidget);
    });

    testWidgets('每个控件都能按 .ui 的 objectName 定位', (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await openSettings(tester);

      // 需求：所有组件的 objectName 改为 ui 的 objectName。
      // 这里逐个点名检查设置页里的每一个控件。
      const List<String> names = <String>[
        kGroupBoxXhq,
        kTableWidgetXh,
        kPushButtonXhhq,
        kGroupBoxHkq,
        kPushButtonHklj,
        kGroupBoxShq,
        kLineEditShqz,
        kPushButtonShqlj,
        kPushButtonShqdk,
        kGroupBoxDl,
        kPushButtonDllj,
        kGroupBoxTz,
        kComboBoxTzxx,
        kLineEditTz,
        kPushButtonDllj2,
      ];
      for (final String name in names) {
        expect(
          byObjectName(name),
          findsWidgets,
          reason: '$name 应按 objectName 可定位',
        );
      }
    });

    testWidgets('四个勾选框是开关样式，文案按各自所属的区区分',
        (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await openSettings(tester);

      // 需求指定「选择框使用开关样式」：四个 QCheckBox 都画成 SwitchRow。
      expect(
        find.descendant(
          of: find.byType(SettingsPanel),
          matching: find.byType(SwitchRow),
        ),
        findsNWidgets(4),
      );
      // 开关轨道也是四个，说明真的画成了开关而不是只包了一层。
      expect(
        find.descendant(
          of: find.byType(SettingsPanel),
          matching: find.byType(SwitchTrack),
        ),
        findsNWidgets(4),
      );

      // 文案照抄 .ui：启用小号 / 启用滑块 / 启用代理 ×2。
      // .ui 里 checkBox_qydl 与 checkBox_qydl_2 都写「启用代理」，照实保留。
      expect(find.text('启用小号'), findsOneWidget);
      expect(find.text('启用滑块'), findsOneWidget);
      expect(find.text('启用代理'), findsNWidgets(2));

      // 方框勾选不该再出现在设置页里。
      expect(
        find.descendant(
          of: find.byType(SettingsPanel),
          matching: find.byType(CheckBoxRow),
        ),
        findsNothing,
      );
    });
  });

  group('与左栏同一套控件', () {
    testWidgets('输入框用 LabeledField / BareField（与登录区同款）',
        (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await openSettings(tester);

      // 登录区的三个输入框在抽屉打开时仍然在树里（左栏不被抽屉遮挡）。
      final List<LabeledField> all = tester
          .widgetList<LabeledField>(find.byType(LabeledField))
          .toList();
      final Set<String> labels =
          all.map((LabeledField f) => f.label).toSet();
      expect(labels, containsAll(<String>{'账户', '密码', '支付密码'}));
      expect(labels, contains('前缀'));

      // 行高统一 30：设置页的输入框与登录区一样高。
      final LabeledField accountField = all.firstWhere(
        (LabeledField f) => f.label == '账户',
      );
      final Rect account = tester.getRect(find.byWidget(accountField));
      expect(account.height, kRowHeight);

      // 通知区用的是 BareField（无标签、独占一格），与 lineEdit_cpxx_2 同一个
      // 组件 —— 两处「没有标签的输入框」不该长得不一样。
      final Rect tz = tester.getRect(byObjectName(kLineEditTz));
      expect(tz.height, kRowHeight);
    });

    testWidgets('卡片标题与登录区同一个样式（主色小标题，压在卡片内）',
        (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await openSettings(tester);

      // 设置页五张卡片都是 PanelGroupBox（与左栏四张卡片同款）。
      final List<PanelGroupBox> boxes = tester
          .widgetList<PanelGroupBox>(find.byType(PanelGroupBox))
          .where((PanelGroupBox b) => <String>[
                '小号区',
                '滑块区',
                '上号器区',
                '代理区',
                '通知区',
              ].contains(b.title))
          .toList();
      expect(boxes.length, 5);

      // 标题用 SectionLabel（主色 w600），不是上一版「压在边框上的居中标题」。
      final Finder settingBox = find
          .ancestor(
            of: find.text('小号区'),
            matching: find.byType(PanelGroupBox),
          )
          .first;
      expect(
        find.descendant(of: settingBox, matching: find.byType(SectionLabel)),
        findsOneWidget,
      );
    });
  });

  group('布置', () {
    testWidgets('卡片铺满抽屉内容区，右侧没有多余空白', (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await openSettings(tester);

      // 抽屉内容区（SlideOutDrawer 里的滚动容器）与卡片的右边界应当只差内边距。
      final Rect drawer = tester.getRect(find.byType(SlideOutDrawer));
      final Rect card = tester.getRect(
        find
            .ancestor(
              of: find.text('小号区'),
              matching: find.byType(PanelGroupBox),
            )
            .first,
      );

      // 上一版画布锁死 311，卡片右边界离抽屉右边缘还有 49px 空白。
      expect(
        drawer.right - card.right,
        closeTo(kDrawerContentPadding.right, 1.5),
        reason: '卡片应铺到抽屉内边距处（抽屉 ${drawer.right} / 卡片 ${card.right}）',
      );
    });

    testWidgets('五张卡片左边界对齐、宽度一致', (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await openSettings(tester);

      final List<Rect> cards = <Rect>[
        for (final String t in <String>[
          '小号区',
          '滑块区',
          '上号器区',
          '代理区',
          '通知区',
        ])
          tester.getRect(
            find
                .ancestor(
                  of: find.text(t),
                  matching: find.byType(PanelGroupBox),
                )
                .first,
          ),
      ];
      expect(cards.length, 5);
      for (final Rect r in cards) {
        expect(r.left, closeTo(cards[0].left, 0.5));
        expect(r.width, closeTo(cards[0].width, 0.5));
      }
    });

    testWidgets('行距不再是 0~2px：卡片之间有真实的空白', (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await openSettings(tester);

      final Rect sub = tester.getRect(
        find
            .ancestor(
              of: find.text('小号区'),
              matching: find.byType(PanelGroupBox),
            )
            .first,
      );
      final Rect slider = tester.getRect(
        find
            .ancestor(
              of: find.text('滑块区'),
              matching: find.byType(PanelGroupBox),
            )
            .first,
      );

      // 上一版卡片 y 紧贴（0..191 / 190..241，甚至重叠 1px）。
      expect(
        slider.top - sub.bottom,
        closeTo(kSettingCardGap, 1.0),
        reason: '卡片间距应为 $kSettingCardGap',
      );
    });
  });

  group('代理区与通知区：所有控件同一行', () {
    testWidgets('代理区：提示 / 按钮 / 开关纵向中心一致', (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await openSettings(tester);

      final Finder card = byObjectName(kGroupBoxDl);
      final Rect tip = tester.getRect(
        find.descendant(of: card, matching: find.byType(SettingTip)),
      );
      final Rect button = tester.getRect(
        find.descendant(of: card, matching: byObjectName(kPushButtonDllj)),
      );
      final Rect sw = tester.getRect(
        find.descendant(of: card, matching: find.byType(SwitchRow)),
      );

      // ignore: avoid_print
      print('代理区: 提示 ${tip.center.dy.toStringAsFixed(1)} '
          '按钮 ${button.center.dy.toStringAsFixed(1)} '
          '开关 ${sw.center.dy.toStringAsFixed(1)}');

      expect(button.center.dy, closeTo(tip.center.dy, 1.5));
      expect(sw.center.dy, closeTo(tip.center.dy, 1.5));

      // 顺序：提示在左、按钮居中、开关在右。
      expect(tip.right, lessThanOrEqualTo(button.left));
      expect(button.right, lessThanOrEqualTo(sw.left));
    });

    testWidgets('通知区：下拉 / 输入框 / 按钮 / 开关纵向中心一致',
        (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await openSettings(tester);

      final Finder card = byObjectName(kGroupBoxTz).last;
      final Rect combo = tester.getRect(
        find.descendant(of: card, matching: byObjectName(kComboBoxTzxx)),
      );
      final Rect field = tester.getRect(
        find.descendant(of: card, matching: byObjectName(kLineEditTz)),
      );
      final Rect button = tester.getRect(
        find.descendant(of: card, matching: byObjectName(kPushButtonDllj2)),
      );
      final Rect sw = tester.getRect(
        find.descendant(of: card, matching: find.byType(SwitchRow)),
      );

      // ignore: avoid_print
      print('通知区: 下拉 ${combo.center.dy.toStringAsFixed(1)} '
          '输入框 ${field.center.dy.toStringAsFixed(1)} '
          '按钮 ${button.center.dy.toStringAsFixed(1)} '
          '开关 ${sw.center.dy.toStringAsFixed(1)}');

      // 四件纵向中心一致 —— 需求「通知区的组件都需要在同一行」。
      expect(field.center.dy, closeTo(combo.center.dy, 1.5));
      expect(button.center.dy, closeTo(combo.center.dy, 1.5));
      expect(sw.center.dy, closeTo(combo.center.dy, 1.5));

      // 顺序：下拉 → 输入框 → 按钮 → 开关，与 .ui 的 x 顺序一致。
      expect(combo.right, lessThanOrEqualTo(field.left));
      expect(field.right, lessThanOrEqualTo(button.left));
      expect(button.right, lessThanOrEqualTo(sw.left));

      // 四件都在卡片内部，且没有溢出（超宽会画黄黑警示条）。
      expect(tester.takeException(), isNull);
    });
  });

  group('勾选交互', () {
    testWidgets('点开关能切换状态', (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await openSettings(tester);

      expect(panel(tester).checkBoxQyxh, isFalse);
      await tester.tap(find.text('启用小号'));
      await tester.pumpAndSettle();
      expect(panel(tester).checkBoxQyxh, isTrue);

      expect(panel(tester).checkBoxQyhk, isFalse);
      await tester.tap(find.text('启用滑块'));
      await tester.pumpAndSettle();
      expect(panel(tester).checkBoxQyhk, isTrue);

      // 两个「启用代理」（代理区 / 通知区）互不影响。
      expect(panel(tester).checkBoxQydl, isFalse);
      expect(panel(tester).checkBoxQydl2, isFalse);
      await tester.tap(find.text('启用代理').first);
      await tester.pumpAndSettle();
      expect(panel(tester).checkBoxQydl, isTrue);
      expect(panel(tester).checkBoxQydl2, isFalse);
    });

    testWidgets('圆钮有滑动动画，不是瞬移', (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await openSettings(tester);

      // 直接量圆钮（AnimatedAlign 里面那颗 12px 圆形 Container）的实际位置。
      Finder knobIn(int index) => find.descendant(
        of: find.byType(SwitchTrack).at(index),
        matching: find.byWidgetPredicate(
          (Widget w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).shape == BoxShape.circle,
        ),
      );

      final Rect before = tester.getRect(knobIn(0));

      await tester.tap(find.text('启用小号'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      final Rect mid = tester.getRect(knobIn(0));
      await tester.pumpAndSettle();
      final Rect after = tester.getRect(knobIn(0));

      final double travel = after.left - before.left;
      final double midTravel = mid.left - before.left;

      expect(travel, greaterThan(0), reason: '开关应真的把圆钮移到右侧');
      expect(midTravel, greaterThan(0), reason: '点击后应已开始移动');
      expect(midTravel, lessThan(travel), reason: '中途不该已经到位，说明不是瞬移');
    });
  });

  group('数据与输入', () {
    testWidgets('小号表预置 10 条数据，框内可滚动', (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await openSettings(tester);

      expect(panel(tester).subAccounts.length, 10);
      expect(find.text('暂无小号'), findsNothing);

      // 10 条超过上限 5 行 —— 表格高度封顶，框内滚动。
      final Rect table = tester.getRect(byObjectName(kTableWidgetXh));
      expect(table.height, settingTableHeightFor(kSettingTableMaxRows));

      expect(
        find.descendant(
          of: byObjectName(kTableWidgetXh),
          matching: find.text('13800138000'),
        ),
        findsOneWidget,
      );

      await tester.drag(byObjectName(kTableWidgetXh), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: byObjectName(kTableWidgetXh),
          matching: find.text('13000130009'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('no 列比 phone / token 窄，不浪费宽度', (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await openSettings(tester);

      // no 列外面套了一个固定宽的 SizedBox（见 _cellSlot(0, ...)），直接量它。
      final Rect noSlot = tester.getRect(
        find
            .ancestor(
              of: find
                  .descendant(
                    of: byObjectName(kTableWidgetXh),
                    matching: find.text('no'),
                  )
                  .first,
              matching: find.byType(SizedBox),
            )
            .first,
      );

      // phone / token 是 Expanded 平分剩余宽度，没有固定的 SizedBox，
      // 所以用两列文本左边界之差推出格子宽（两处 Padding 都是 6，差值正好是格宽）。
      double leftOf(String text) => tester
          .getRect(
            find
                .descendant(
                  of: byObjectName(kTableWidgetXh),
                  matching: find.text(text),
                )
                .first,
          )
          .left;
      final double phoneWidth = leftOf('token') - leftOf('phone');

      // ignore: avoid_print
      print('列宽: no=${noSlot.width} phone=$phoneWidth');
      expect(noSlot.width, kSettingTableNoWidth);
      expect(phoneWidth, greaterThan(noSlot.width * 3));
    });

    testWidgets('点「获取」后列表顺序改变，说明按钮生效', (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await openSettings(tester);

      final String firstBefore = panel(tester).subAccounts.first.phone;
      await tester.tap(find.text('获取'));
      await tester.pumpAndSettle();
      expect(panel(tester).subAccounts.first.phone, isNot(firstBefore));
    });

    testWidgets('上号器区输入框内容在关闭抽屉后不丢失', (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await openSettings(tester);

      await tester.enterText(byObjectName(kLineEditShqz), 'abc123');
      await tester.pumpAndSettle();

      // 关掉抽屉再开回来。
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(
        panel(tester).lineEditShqzController.text,
        'abc123',
        reason: '控制器归页面持有，不该丢',
      );
    });

    testWidgets('上号器区只有前缀一个输入框，格式说明在标题里',
        (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await openSettings(tester);

      // config.ui 把 groupBox_shq 的高度从 71 收到 51，并删掉了 lineEdit_3：
      // 那一区现在只剩一行控件，格式说明变成标题的一部分。
      final Finder loaderBox = byObjectName(kGroupBoxShq);

      expect(
        find.descendant(of: loaderBox, matching: find.byType(LabeledField)),
        findsOneWidget,
        reason: '只剩「前缀」一个输入框',
      );
      // 副标题就是 .ui 标题里的那半句。
      expect(
        find.descendant(
          of: loaderBox,
          matching: find.text('格式：前缀-手机号-密码-支付密码'),
        ),
        findsOneWidget,
      );
      // 一行控件 + 标题 + 副标题：卡片高度应明显低于「两个输入框」的版本。
      expect(tester.getRect(loaderBox).height, lessThan(150));
    });

    testWidgets('通知区的下拉有 .ui 里的三个候选', (WidgetTester tester) async {
      setSurface(tester, kDesignWidth, kDesignHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await openSettings(tester);

      final PanelDropdown combo = tester.widget<PanelDropdown>(
        byObjectName(kComboBoxTzxx),
      );
      expect(combo.items, <String>['息知', 'wxpur', 'baerk']);
      expect(combo.value, '息知', reason: '默认选中 .ui 的第一项');
    });
  });

  group('布局', () {
    testWidgets('最小窗口下设置页不溢出', (WidgetTester tester) async {
      setSurface(tester, kMinWidth, kMinHeight);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await openSettings(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets('极窄窗口下设置页不溢出', (WidgetTester tester) async {
      setSurface(tester, 640, 480);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await openSettings(tester);

      expect(tester.takeException(), isNull);
    });
  });
}
