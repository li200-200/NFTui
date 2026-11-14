// ---------------------------------------------------------------------------
// 设置页的补充控件
//
// 【这个文件为什么只剩一个小组件】
// 上一版这里有三个「按 config.ui 绝对坐标绘制」的原子件：SettingLabel（独立
// QLabel）、SettingLineEdit（20 高输入框）、SettingCheckBox（71x21 方框勾选），
// 以及一个把标题压在边框上的 SettingGroupBox。
//
// 需求改成「优化布置」之后，设置区不再逐像素复刻 .ui，而是**复用左栏那套控件**：
//   · 输入框 → LabeledField（与登录区「账户 / 密码 / 支付密码」同一个组件，
//     标签格 60、行高 30、聚焦时同一套外发光）；
//   · 勾选框 → SwitchRow（开关样式，需求指定）；
//   · 卡片   → PanelGroupBox（标题与「登录区 / 信息区 / 选项区」同一套样式）；
//   · 按钮   → PanelButton（与「发送 / 登录」同高 23）。
// 那三个原子件因此全部删除 —— 留着只会诱使后来者再画一套不一致的控件。
//
// 唯一还需要单独写的是「说明文字」：.ui 里 label_3 / label_4 那种以 `*` 开头的
// 提示，在左栏没有对应物（左栏的提示都塞进 hint 里了），所以留在这里。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';

/// 分组内的说明文字（对应 config.ui 里 label_3 / label_4 那种 `*` 开头的提示）。
///
/// 用辅助色而不是主文字色：它是「说明这个区怎么用」的附注，不该与真正的字段
/// 标签抢注意力。
///
/// 两种排法由 [inline] 决定：
///   · false（默认）—— 独占一行，允许折到两行。抽屉窄的时候「*使用工具先获取
///     小号数据」一行放不下，截成省略号会丢掉半句关键信息；
///   · true —— 与开关、按钮挤在同一排，此时必须单行，靠 [FittedBox] 按比例缩
///     到刚好放下（缩 0.98 肉眼看不出，折行却会把这一排撑成两行高）。
class SettingTip extends StatelessWidget {
  const SettingTip({super.key, required this.text, this.inline = false});

  final String text;

  /// true = 与其它控件同排显示：单行 + 自动缩放，既不折行也不截断。
  final bool inline;

  @override
  Widget build(BuildContext context) {
    const TextStyle style = TextStyle(
      fontSize: kFontHint,
      color: WorkColors.textMuted,
      fontFamily: kFontFamily,
      fontFamilyFallback: kFontFallback,
      height: 1.35,
    );

    if (inline) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: style,
        ),
      );
    }

    return Text(text, maxLines: 2, style: style);
  }
}
