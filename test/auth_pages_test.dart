// ---------------------------------------------------------------------------
// 验证页（登录 / 注册 / 充值）的界面契约测试
//
// 这些断言盯的是「与参考图逐像素对齐」这件事：尺寸、比例、控件位置关系。
// 一旦有人改了 theme.dart 里的 kAuth* 常量，或者调整了 auth_scaffold 的分栏，
// 这里会立刻失败 —— 而不是等用户看到界面说「怎么变形了」。
//
// 【为什么用固定尺寸 pump 而不是按窗口自适应】
// 验证页是锁定尺寸的（原生层把最小=最大=800x550 锁死），不存在「窗口拉大后
// 布局怎么变」的问题。所以这里直接按 800x550 建表面，测的就是真实运行时的
// 那个几何。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_ui/pages/login_page.dart';
import 'package:app_ui/pages/recharge_page.dart';
import 'package:app_ui/pages/register_page.dart';
import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/auth_controls.dart';
import 'package:app_ui/widgets/illustration_panel.dart';
import 'package:app_ui/widgets/window_chrome.dart';

/// 花瓣是无限循环动画，widget 测试里会让 pumpAndSettle 永远等不到「没有待处理
/// 帧」。这里静态画一帧就停 —— 与参考工程的做法一致。
void _freezePetals() {
  IllustrationPanel.petalsEnabled = false;
}

Widget _wrap(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: Scaffold(
      backgroundColor: AuthColors.surface,
      body: SizedBox(
        width: kAuthWidth,
        height: kAuthHeight,
        child: child,
      ),
    ),
  );
}

void main() {
  setUp(_freezePetals);

  group('骨架比例', () {
    testWidgets('左插画 40% / 右表单 60%', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          LoginPage(
            onGoRegister: () {},
            onGoRecharge: () {},
            onLoginSuccess: (_) {},
            credPath: '',
          ),
        ),
      );
      await tester.pump();

      final Rect panel = tester.getRect(find.byType(IllustrationPanel));
      // 800 的 40% = 320。允许 1px 的浮点误差。
      expect(panel.width, closeTo(kAuthWidth * 0.4, 1.0),
          reason: '插画应占窗口 40% 宽，实际 ${panel.width}');
      expect(panel.left, 0, reason: '插画贴左边');
      expect(panel.height, kAuthHeight, reason: '插画纵向铺满');
    });

    testWidgets('表单列宽 280，水平居中于右栏', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          LoginPage(
            onGoRegister: () {},
            onGoRecharge: () {},
            onLoginSuccess: (_) {},
            credPath: '',
          ),
        ),
      );
      await tester.pump();

      // 第一个输入框的宽度就是表单列宽（ConstrainedBox maxWidth 生效）
      final Finder firstField = find.byType(FieldInput).first;
      final Rect field = tester.getRect(firstField);
      expect(field.width, closeTo(kAuthFormWidth, 1.0),
          reason: '表单列应为 $kAuthFormWidth，实际 ${field.width}');

      // 右栏是 [320, 800]，中心 560。表单列中心应当落在那里。
      const double rightPanelCenter = kAuthWidth * 0.4 +
          (kAuthWidth * 0.6) / 2;
      expect(field.center.dx, closeTo(rightPanelCenter, 2.0),
          reason: '表单列应水平居中于右栏，实际中心 ${field.center.dx}');
    });

    testWidgets('右上角有窗口控制区（关闭按钮必在）', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          LoginPage(
            onGoRegister: () {},
            onGoRecharge: () {},
            onLoginSuccess: (_) {},
            credPath: '',
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(WindowControls), findsOneWidget);
      // 登录页是首页，没有上一级 —— 只有关闭，没有返回。
      expect(find.byType(CircleCloseButton), findsOneWidget);
      expect(find.byType(CircleBackButton), findsNothing,
          reason: '登录页不该有返回按钮');

      // 贴在右上角
      final Rect close = tester.getRect(find.byType(CircleCloseButton));
      expect(close.right, greaterThan(kAuthWidth - 40));
      expect(close.top, lessThan(40));
    });

    testWidgets('注册页有返回按钮（有上一级）', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(RegisterPage(onBack: () {}, onRegisterSuccess: (_) {})),
      );
      await tester.pump();

      expect(find.byType(CircleBackButton), findsOneWidget,
          reason: '注册页可以退回登录页');
      expect(find.byType(CircleCloseButton), findsOneWidget);
    });
  });

  group('输入框尺寸与样式', () {
    testWidgets('高度 44、圆角 4、灰底', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          LoginPage(
            onGoRegister: () {},
            onGoRecharge: () {},
            onLoginSuccess: (_) {},
            credPath: '',
          ),
        ),
      );
      await tester.pump();

      final Finder field = find.byType(FieldInput).first;
      expect(tester.getSize(field).height, kFieldHeight,
          reason: '输入框应为 $kFieldHeight 高');

      // 灰底 #F3F3F5 是验证页与工作台最主要的区别，不能被改成白色。
      final AnimatedContainer box = tester.widget<AnimatedContainer>(
        find.descendant(of: field, matching: find.byType(AnimatedContainer)).first,
      );
      final BoxDecoration deco = box.decoration! as BoxDecoration;
      expect(deco.color, AuthColors.fieldFill);
      expect(AuthColors.fieldFill, isNot(Colors.white),
          reason: '验证页输入框是灰底，不是工作台的白底');
      expect(deco.borderRadius, BorderRadius.circular(4));
    });

    testWidgets('两个输入框之间间距 16', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          LoginPage(
            onGoRegister: () {},
            onGoRecharge: () {},
            onLoginSuccess: (_) {},
            credPath: '',
          ),
        ),
      );
      await tester.pump();

      final Finder fields = find.byType(FieldInput);
      expect(fields, findsNWidgets(2), reason: '登录页是用户名 + 密码两栏');

      final Rect a = tester.getRect(fields.at(0));
      final Rect b = tester.getRect(fields.at(1));
      expect(b.top - a.bottom, closeTo(16, 0.5));
    });
  });

  group('按钮', () {
    testWidgets('登录按钮是 160x40 胶囊', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          LoginPage(
            onGoRegister: () {},
            onGoRecharge: () {},
            onLoginSuccess: (_) {},
            credPath: '',
          ),
        ),
      );
      await tester.pump();

      final Finder btn = find.byType(PillButton);
      expect(btn, findsOneWidget);
      expect(tester.getSize(btn), const Size(160, 40));

      // 圆角 = 高度一半 → 两端是完整半圆
      final AnimatedContainer box = tester.widget<AnimatedContainer>(
        find.descendant(of: btn, matching: find.byType(AnimatedContainer)),
      );
      final BoxDecoration deco = box.decoration! as BoxDecoration;
      expect(deco.borderRadius, BorderRadius.circular(20),
          reason: '胶囊圆角 = 高度/2 = 20');
    });
  });

  group('表单校验反馈', () {
    testWidgets('空表单点登录：不出文字，只把两个框标红', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          LoginPage(
            onGoRegister: () {},
            onGoRecharge: () {},
            onLoginSuccess: (_) {},
            credPath: '',
          ),
        ),
      );
      await tester.pump();

      // 提交前没有任何红框
      List<FieldInput> fields =
          tester.widgetList<FieldInput>(find.byType(FieldInput)).toList();
      expect(fields.every((FieldInput f) => !f.hasError), isTrue);

      await tester.tap(find.byType(PillButton));
      await tester.pump();

      fields = tester.widgetList<FieldInput>(find.byType(FieldInput)).toList();
      expect(fields.every((FieldInput f) => f.hasError), isTrue,
          reason: '两个字段都是空的，都该标红');

      // 本地校验失败**不出文字**（错误提示条只在服务端结果时出现）
      expect(find.textContaining('请输入用户名'), findsNothing,
          reason: '本地校验只红框抖动，不显示文案');

      // 抖动是 520ms 的动画，等它跑完再断言，否则 tester 会报「有待处理帧」
      await tester.pumpAndSettle();
    });

    testWidgets('开始输入就把红框收掉', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          LoginPage(
            onGoRegister: () {},
            onGoRecharge: () {},
            onLoginSuccess: (_) {},
            credPath: '',
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(PillButton));
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'abc123');
      await tester.pump();

      final FieldInput userField =
          tester.widgetList<FieldInput>(find.byType(FieldInput)).first;
      expect(userField.hasError, isFalse,
          reason: '一开始改就把红框收掉，不用等下次提交');
    });
  });

  group('各页面的字段数', () {
    testWidgets('登录 2 栏 / 注册 4 栏 / 充值 3 栏', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          LoginPage(
            onGoRegister: () {},
            onGoRecharge: () {},
            onLoginSuccess: (_) {},
            credPath: '',
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(FieldInput), findsNWidgets(2));

      await tester.pumpWidget(
        _wrap(RegisterPage(onBack: () {}, onRegisterSuccess: (_) {})),
      );
      await tester.pump();
      expect(find.byType(FieldInput), findsNWidgets(4),
          reason: '用户名 / 密码 / 确认密码 / 卡密');

      await tester.pumpWidget(
        _wrap(
          RechargePage(onBack: () {}, initialUser: '', onSubmitSuccess: (_) {}),
        ),
      );
      await tester.pump();
      expect(find.byType(FieldInput), findsNWidgets(3),
          reason: '用户名 / 账号密码 / 卡密');
    });

    testWidgets('充值页接收登录页带过来的用户名', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          RechargePage(
            onBack: () {},
            initialUser: 'abc123',
            onSubmitSuccess: (_) {},
          ),
        ),
      );
      await tester.pump();

      // initialUser 应当被预填进第一个输入框
      expect(find.text('abc123'), findsOneWidget);
    });
  });

  group('勾选与链接', () {
    testWidgets('登录页两个勾选框：记住密码 / 自动登录', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          LoginPage(
            onGoRegister: () {},
            onGoRecharge: () {},
            onLoginSuccess: (_) {},
            credPath: '',
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CheckPill), findsNWidgets(2));
      expect(find.text('记住密码'), findsOneWidget);
      expect(find.text('自动登录'), findsOneWidget);
    });

    testWidgets('勾选框是 18x18 方框，不是工作台的开关', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          LoginPage(
            onGoRegister: () {},
            onGoRecharge: () {},
            onLoginSuccess: (_) {},
            credPath: '',
          ),
        ),
      );
      await tester.pump();

      final Finder box = find
          .descendant(
            of: find.byType(CheckPill).first,
            matching: find.byType(AnimatedContainer),
          )
          .first;
      expect(tester.getSize(box), const Size(18, 18));
    });

    testWidgets('勾上「自动登录」会连带勾上「记住密码」', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          LoginPage(
            onGoRegister: () {},
            onGoRecharge: () {},
            onLoginSuccess: (_) {},
            credPath: '',
          ),
        ),
      );
      await tester.pump();

      // 初始：记住密码勾着（默认 true），自动登录没勾
      List<CheckPill> pills =
          tester.widgetList<CheckPill>(find.byType(CheckPill)).toList();
      expect(pills[0].value, isTrue);
      expect(pills[1].value, isFalse);

      // 先取消「记住密码」——「自动登录」应当跟着一起收掉
      await tester.tap(find.text('记住密码'));
      await tester.pump();
      pills = tester.widgetList<CheckPill>(find.byType(CheckPill)).toList();
      expect(pills[0].value, isFalse);

      // 再勾「自动登录」——「记住密码」应当被强制勾上
      await tester.tap(find.text('自动登录'));
      await tester.pump();
      pills = tester.widgetList<CheckPill>(find.byType(CheckPill)).toList();
      expect(pills[1].value, isTrue);
      expect(pills[0].value, isTrue,
          reason: '自动登录依赖保存下来的账号密码，必须连带记住密码');
    });

    testWidgets('页脚三个元素：联系领航 / 我同意 / 软件使用协议', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          LoginPage(
            onGoRegister: () {},
            onGoRecharge: () {},
            onLoginSuccess: (_) {},
            credPath: '',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('联系领航'), findsOneWidget);
      expect(find.text('我同意'), findsOneWidget);
      expect(find.text('软件使用协议'), findsOneWidget);

      // 页脚在右下角
      final Rect agree = tester.getRect(find.text('软件使用协议'));
      expect(agree.right, greaterThan(kAuthWidth - 60));
      expect(agree.bottom, greaterThan(kAuthHeight - 40));
    });
  });
}
