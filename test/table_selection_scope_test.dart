// ---------------------------------------------------------------------------
// 表格的可选中范围：三张任务表 + 小号表
//
// 【这条需求的原文】
//   「订单信息的任务列表与完成的任务列表中的信息不可以选中，右键点击也不会出现
//     菜单。只有运行的任务列表才可以，小号右键点击会弹出菜单，菜单中有全选，
//     删除选中小号。」
//
// 所以这里要钉住四件事：
//   1. 运行表：可以点选、可以右键出菜单（菜单四项）；
//   2. 订单表：点了不变、右键不出菜单；
//   3. 完成表：同上；
//   4. 小号表：可以点选、右键菜单只有「全选 / 删除选中小号」两项。
//
// 【怎么判断「能不能选中」】
// 不截图比对颜色（那样太脆），而是看行为：点一行之后 `selected` 集合有没有变。
// 集合由页面持有，所以从 widget 的属性里读出来即可。
//
// 【怎么判断「右键出不出菜单」】
// 右键后 pumpAndSettle，然后找菜单文案（'全选' 等）。菜单是 Overlay 里的
// 路由，用 find.text 就能拿到。注意：表格为空时菜单也能弹，所以测试数据里
// 必须**有行** —— 否则「点上去没反应」可能只是因为没东西可点。
// ---------------------------------------------------------------------------
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_ui/pages/main_page.dart';
import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/drawer_panels.dart';
import 'package:app_ui/widgets/object_names.dart';
import 'package:app_ui/widgets/setting_table.dart';
import 'package:app_ui/widgets/task_table.dart';

void main() {
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

  /// 取某张任务表当前的选中集合。
  Set<int> selectedOf(WidgetTester tester, String objectName) {
    final TaskTable table = tester.widget<TaskTable>(
      find.byKey(ValueKey<String>(objectName)),
    );
    return table.selected;
  }

  /// 切到某个 Tab。
  Future<void> openTab(WidgetTester tester, String title) async {
    await tester.tap(find.text(title).first);
    await tester.pumpAndSettle();
  }

  group('三张任务表的可选中范围', () {
    testWidgets('运行表：点行能选中', (WidgetTester tester) async {
      await tester.pumpWidget(host(const MainPage()));
      await tester.pumpAndSettle();

      // 默认就在「运行」Tab。取第一行数据（phone 列的文字）点它。
      final Finder firstPhone = find.text('13800138000').first;
      expect(firstPhone, findsOneWidget);

      await tester.tap(firstPhone);
      await tester.pumpAndSettle();

      expect(selectedOf(tester, kTableWidgetYx), isNotEmpty,
          reason: '运行表是唯一可以选中的任务表');
    });

    testWidgets('运行表：右键弹出四项菜单', (WidgetTester tester) async {
      await tester.pumpWidget(host(const MainPage()));
      await tester.pumpAndSettle();

      final Finder row = find.text('13800138000').first;
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(row),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('全选'), findsOneWidget);
      expect(find.text('反选'), findsOneWidget);
      expect(find.text('删除选中'), findsOneWidget);
      expect(find.text('删除成功'), findsOneWidget);
    });

    testWidgets('订单表：点行选不中', (WidgetTester tester) async {
      await tester.pumpWidget(host(const MainPage()));
      await tester.pumpAndSettle();
      await openTab(tester, '订单信息');

      // 订单表的第一行手机号
      final Finder phone = find.text('13800138000');
      expect(phone, findsWidgets);

      await tester.tap(phone.first);
      await tester.pumpAndSettle();

      expect(selectedOf(tester, kTableWidgetDdxx), isEmpty,
          reason: '订单信息是只读快照，不该能选中');
    });

    testWidgets('订单表：右键不出菜单', (WidgetTester tester) async {
      await tester.pumpWidget(host(const MainPage()));
      await tester.pumpAndSettle();
      await openTab(tester, '订单信息');

      final Finder row = find.text('13800138000').first;
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(row),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('全选'), findsNothing,
          reason: '订单表右键不该弹出菜单');
      expect(find.text('删除选中'), findsNothing);
    });

    testWidgets('完成表：点行选不中、右键不出菜单', (WidgetTester tester) async {
      await tester.pumpWidget(host(const MainPage()));
      await tester.pumpAndSettle();
      await openTab(tester, '完成');

      final Finder row = find.text('13800138000').first;
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(selectedOf(tester, kTableWidgetWc), isEmpty,
          reason: '完成表是只读快照，不该能选中');

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(row),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('全选'), findsNothing,
          reason: '完成表右键不该弹出菜单');
    });
  });

  group('小号表的选中与右键菜单', () {
    /// 打开设置抽屉（小号表在那里）。
    Future<void> openSettings(WidgetTester tester) async {
      await tester.pumpWidget(host(const MainPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
    }

    /// 小号表在设置抽屉里，抽屉是纵向滚动的 —— 内容高于窗口时表格可能落在
    /// 视口外，此时 tester.tap 会报「widget is off-screen」。
    /// 先把它滚进视野再操作。
    Future<Finder> scrollToTable(WidgetTester tester) async {
      final Finder table = find.byKey(const ValueKey<String>(kTableWidgetXh));
      await tester.scrollUntilVisible(
        table,
        200,
        scrollable: find.descendant(
          of: find.byType(SettingsPanel),
          matching: find.byType(Scrollable),
        ).first,
      );
      await tester.pumpAndSettle();
      return table;
    }

    /// 在小号表里点第 [index] 行（按手机号定位，不依赖 no 列的数字）。
    Future<void> tapRow(WidgetTester tester, String phone) async {
      final Finder row = find.descendant(
        of: find.byKey(const ValueKey<String>(kTableWidgetXh)),
        matching: find.text(phone),
      );
      expect(row, findsOneWidget, reason: '小号表里应能按手机号定位到 $phone');
      await tester.tap(row);
      await tester.pumpAndSettle();
    }

    /// 在小号表里右键第 [phone] 行。
    Future<void> rightClickRow(WidgetTester tester, String phone) async {
      final Finder row = find.descendant(
        of: find.byKey(const ValueKey<String>(kTableWidgetXh)),
        matching: find.text(phone),
      );
      expect(row, findsOneWidget);
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(row),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
    }

    SubAccountTable tableWidget(WidgetTester tester) =>
        tester.widget<SubAccountTable>(
          find.byKey(const ValueKey<String>(kTableWidgetXh)),
        );

    testWidgets('点小号行能选中', (WidgetTester tester) async {
      await openSettings(tester);
      await scrollToTable(tester);

      expect(tableWidget(tester).selected, isEmpty, reason: '初始没有选中');

      await tapRow(tester, '13800138000');
      expect(tableWidget(tester).selected, contains(0),
          reason: '点第一行应选中下标 0');
    });

    testWidgets('再点一次取消选中', (WidgetTester tester) async {
      await openSettings(tester);
      await scrollToTable(tester);

      await tapRow(tester, '13800138000');
      await tapRow(tester, '13800138000');

      expect(tableWidget(tester).selected, isEmpty, reason: '再点一次应取消');
    });

    testWidgets('右键菜单只有「全选 / 删除选中小号」两项', (WidgetTester tester) async {
      await openSettings(tester);
      await scrollToTable(tester);
      await rightClickRow(tester, '13800138000');

      expect(find.text('全选'), findsOneWidget);
      expect(find.text('删除选中小号'), findsOneWidget);
      // 这两项是小号表**没有**的 —— 小号没有状态机，不需要按状态筛行。
      expect(find.text('反选'), findsNothing);
      expect(find.text('删除成功'), findsNothing);
    });

    testWidgets('菜单「全选」选中所有小号', (WidgetTester tester) async {
      await openSettings(tester);
      await scrollToTable(tester);

      final int rowCount = tableWidget(tester).rows.length;
      expect(rowCount, greaterThan(0));

      await rightClickRow(tester, '13800138000');
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();

      expect(tableWidget(tester).selected.length, rowCount,
          reason: '全选应覆盖每一行');
    });

    testWidgets('菜单「删除选中小号」真的把行删掉', (WidgetTester tester) async {
      await openSettings(tester);
      await scrollToTable(tester);

      final int before = tableWidget(tester).rows.length;

      await tapRow(tester, '13800138000');
      await rightClickRow(tester, '13800138000');
      await tester.tap(find.text('删除选中小号'));
      await tester.pumpAndSettle();

      expect(tableWidget(tester).rows.length, before - 1, reason: '应删掉一行');
      expect(tableWidget(tester).selected, isEmpty, reason: '删完选中集合要清空');
    });

    testWidgets('没选中就点删除，只提示不删行', (WidgetTester tester) async {
      await openSettings(tester);
      await scrollToTable(tester);

      final int before = tableWidget(tester).rows.length;

      await rightClickRow(tester, '13800138000');
      await tester.tap(find.text('删除选中小号'));
      await tester.pumpAndSettle();

      expect(tableWidget(tester).rows.length, before, reason: '没选中不该删任何行');
      expect(find.text('请先选中小号'), findsOneWidget,
          reason: '要给出明确提示，而不是静默什么都不做');
    });
  });
}
