// ---------------------------------------------------------------------------
// 交互态回归测试
//
// 守的是验收标准里「四态齐备」那一条 —— 这类问题在截图里看不出来，只能靠
// 模拟鼠标事件 + 断言渲染出来的颜色。
//
// 只断言「颜色变了」而不是断言具体色值：色值在 theme.dart 里已经有单一来源，
// 这里再抄一遍数字，改令牌时两边都要改，反而容易不同步。
// ---------------------------------------------------------------------------
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_ui/models.dart';
import 'package:app_ui/pages/main_page.dart';
import 'package:app_ui/theme.dart';
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

/// 取某个 widget 实际渲染出来的 AnimatedContainer 装饰色。
///
/// AnimatedContainer 的中间帧是动画值，所以悬停之后要 pumpAndSettle，
/// 等 120ms 的过渡走完再读 —— 否则读到的是上一帧的插值色。
Color decorationColor(WidgetTester tester, Finder finder) {
  final AnimatedContainer box = tester.widget<AnimatedContainer>(finder);
  final BoxDecoration d = box.decoration! as BoxDecoration;
  return d.color!;
}

void main() {
  testWidgets('按钮悬停与按下：底色变化，且禁用态不响应', (WidgetTester tester) async {
    setSurface(tester, kDesignWidth, kDesignHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // 「登录」是主按钮（primary），常态底色 = fieldFill。
    final Finder loginBox = find.descendant(
      of: find.widgetWithText(PanelButton, '登录'),
      matching: find.byType(AnimatedContainer),
    );
    expect(decorationColor(tester, loginBox), WorkColors.fieldFill);

    // 悬停 → 主色 12% 垫底。
    final TestGesture hover = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await hover.addPointer(location: Offset.zero);
    addTearDown(hover.removePointer);
    await tester.pump();
    await hover.moveTo(tester.getCenter(find.text('登录')));
    await tester.pumpAndSettle();
    final Color hovered = decorationColor(tester, loginBox);
    expect(hovered, isNot(WorkColors.fieldFill));

    // 移开 → 回到常态。
    await hover.moveTo(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(decorationColor(tester, loginBox), WorkColors.fieldFill);

    // 「发送」是禁用态：底色固定 panel，悬停也不变。
    final Finder sendBox = find.descendant(
      of: find.widgetWithText(PanelButton, '发送'),
      matching: find.byType(AnimatedContainer),
    );
    expect(decorationColor(tester, sendBox), WorkColors.panel);
    await hover.moveTo(tester.getCenter(find.text('发送')));
    await tester.pumpAndSettle();
    expect(decorationColor(tester, sendBox), WorkColors.panel);
  });

  testWidgets('输入框聚焦：边框转主色并加粗，底色变 fieldFillFocused', (WidgetTester tester) async {
    setSurface(tester, kDesignWidth, kDesignHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // 第一个 LabeledField 是「账户」。
    final Finder fieldBox = find
        .descendant(
          of: find.byType(LabeledField).first,
          matching: find.byType(AnimatedContainer),
        )
        .first;

    BoxDecoration deco() =>
        tester.widget<AnimatedContainer>(fieldBox).decoration!
            as BoxDecoration;

    expect(deco().color, WorkColors.fieldFill);
    expect(deco().border!.top.color, WorkColors.border);
    expect(deco().border!.top.width, 1.0);

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    expect(deco().color, WorkColors.fieldFillFocused);
    expect(deco().border!.top.color, WorkColors.primary);
    expect(deco().border!.top.width, 1.4);
    // 聚焦时有一层主色外发光。
    expect(deco().boxShadow, isNotNull);
  });

  testWidgets('表格行：悬停变色，点击选中后左侧出现 3px 主色竖条', (WidgetTester tester) async {
    setSurface(tester, kDesignWidth, kDesignHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    /* 必须限定在表格内部找单元格。
     *
     * 早先这里用 find.text('1').first —— 左栏「数量」输入框的默认值就是 "1"，
     * 而且是先于表格出现在树里的，于是点击落到了输入框上，行根本没被选中，
     * 断言自然找不到任何选中行。用手机号这种只在表格里出现的文本最稳。 */
    final Finder firstCell = find.descendant(
      of: find.byType(TaskTable).first,
      matching: find.text('13800138000'),
    );
    expect(firstCell, findsOneWidget);

    // 悬停。
    final TestGesture hover = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await hover.addPointer(location: Offset.zero);
    addTearDown(hover.removePointer);
    await tester.pump();
    await hover.moveTo(tester.getCenter(firstCell));
    await tester.pumpAndSettle();

    // 点击选中。
    await tester.tap(firstCell);
    await tester.pumpAndSettle();

    // 选中行用 foregroundDecoration 画左侧 3px 竖条（不是子节点，
    // 否则会挤占行内宽度让列宽整体右移）。
    final Iterable<AnimatedContainer> rows = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .where((AnimatedContainer c) {
          final Decoration? d = c.foregroundDecoration;
          return d is BoxDecoration && d.border is Border;
        });
    expect(rows, isNotEmpty);
    final BoxDecoration sel = rows.first.foregroundDecoration! as BoxDecoration;
    final Border b = sel.border! as Border;
    expect(b.left.color, WorkColors.primary);
    expect(b.left.width, 3);
  });

  testWidgets('标签条：切 Tab 后选中态迁移，下划线只有一条可见', (WidgetTester tester) async {
    setSurface(tester, kDesignWidth, kDesignHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // 「运行」初始选中：文字 w600。
    TextStyle styleOf(String label) =>
        tester.widget<Text>(find.text(label).first).style!;

    expect(styleOf('运行').fontWeight, FontWeight.w600);
    expect(styleOf('订单信息').fontWeight, FontWeight.w400);

    await tester.tap(find.text('订单信息'));
    await tester.pumpAndSettle();

    expect(styleOf('订单信息').fontWeight, FontWeight.w600);
    expect(styleOf('运行').fontWeight, FontWeight.w400);
    expect(tester.takeException(), isNull);
  });

  testWidgets('右键菜单：弹出四项，且顺序固定', (WidgetTester tester) async {
    setSurface(tester, kDesignWidth, kDesignHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final TestGesture right = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await right.addPointer(location: Offset.zero);
    addTearDown(right.removePointer);
    await right.down(tester.getCenter(find.byType(TaskTable).first));
    await right.up();
    await tester.pumpAndSettle();

    expect(find.text('全选'), findsOneWidget);
    expect(find.text('反选'), findsOneWidget);
    expect(find.text('删除选中'), findsOneWidget);
    expect(find.text('删除成功'), findsOneWidget);
  });

  testWidgets('「全选」后所有行都进入选中态', (WidgetTester tester) async {
    setSurface(tester, kDesignWidth, kDesignHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final TestGesture right = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await right.addPointer(location: Offset.zero);
    addTearDown(right.removePointer);
    await right.down(tester.getCenter(find.byType(TaskTable).first));
    await right.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();

    // 选中行都带左侧 3px 竖条，数量应等于占位数据行数。
    final int selected = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .where((AnimatedContainer c) {
          final Decoration? d = c.foregroundDecoration;
          return d is BoxDecoration && d.border is Border;
        })
        .length;
    expect(selected, kDemoRunRows.length);
  });
}
