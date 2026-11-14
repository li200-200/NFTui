// ---------------------------------------------------------------------------
// 布局对齐回归测试
//
// 这两条都是「肉眼一看就该对、但改别的很容易改回去」的性质，钉在这里：
//   1. 左栏所有标签格同宽 —— 否则各输入框的左边界落在不同竖线上；
//   2. 最小化 / 关闭贴住标题条最右端 —— 否则标题抢走剩余空间把按钮推到中间。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_ui/pages/main_page.dart';
import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/panel_controls.dart';

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
  testWidgets('左栏所有 LabeledField 的输入格左边界对齐', (WidgetTester tester) async {
    setSurface(tester, kDesignWidth, kDesignHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final List<LabeledField> fields = tester
        .widgetList<LabeledField>(find.byType(LabeledField))
        .toList();
    expect(fields.length, 8, reason: '登录区 3 个 + 信息区 4 个 + 操作区 1 个');

    // 全部用同一个标签格宽度。
    for (final LabeledField f in fields) {
      expect(f.labelWidth, kLabelWidth, reason: '「${f.label}」的标签格宽度应统一');
    }

    // 落到屏幕上：每个 LabeledField 里的 TextField 全局左坐标必须完全一致。
    //
    // 只查 LabeledField 内部的 TextField —— 信息区那个无标签的 `key` 回填框
    // （.ui 的 lineEdit_cpxx_2）本来就是整行 181 宽、不参与两格对齐，把它算进
    // 来会让这条断言失去意义。
    final List<TextField> inputs = <TextField>[
      for (final Element e in find.byType(LabeledField).evaluate())
        ...tester.widgetList<TextField>(
          find.descendant(
            of: find.byWidget(e.widget),
            matching: find.byType(TextField),
          ),
        ),
    ];
    expect(inputs.length, 8);
    final Set<double> lefts = <double>{
      for (final Element e in find.byType(LabeledField).evaluate())
        tester
            .getTopLeft(
              find
                  .descendant(
                    of: find.byWidget(e.widget),
                    matching: find.byType(TextField),
                  )
                  .first,
            )
            .dx,
    };
    expect(lefts.length, 1, reason: '所有输入框左边界应落在同一条竖线上，实测：$lefts');
  });

  testWidgets('最小化 / 关闭贴住标题条最右端', (WidgetTester tester) async {
    setSurface(tester, kDesignWidth, kDesignHeight);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // 关闭按钮的右边界 + 标题条右内边距 6 = 窗口右边界。
    final double closeRight = tester.getTopRight(find.byIcon(Icons.close)).dx;
    final double windowRight = tester.getTopRight(find.byType(MaterialApp)).dx;

    // 图标本身比按钮窄（按钮 30、图标 15），所以图标右边到窗口右边大约是
    // 内边距 6 + 图标左右各 (30-15)/2 = 6 + 7.5 ≈ 13.5。
    expect(
      windowRight - closeRight,
      closeTo(13.5, 1.5),
      reason: '关闭按钮应贴在标题条最右侧，实测间距 ${windowRight - closeRight}',
    );

    // 最小化必须在关闭左边（顺序：最小化 → 关闭）。
    final double minLeft = tester.getTopLeft(find.byIcon(Icons.remove)).dx;
    final double closeLeft = tester.getTopLeft(find.byIcon(Icons.close)).dx;
    expect(minLeft, lessThan(closeLeft));
  });

  testWidgets('窗口拉宽后按钮仍然贴右，不随标题变长而左移', (WidgetTester tester) async {
    setSurface(tester, 1400, 682);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final double closeRight = tester.getTopRight(find.byIcon(Icons.close)).dx;
    final double windowRight = tester.getTopRight(find.byType(MaterialApp)).dx;
    expect(windowRight - closeRight, closeTo(13.5, 1.5));
  });
}
