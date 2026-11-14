// ---------------------------------------------------------------------------
// 开关（Switch）—— 设置页的「启用小号 / 启用滑块」用
//
// 【为什么不用 CheckBoxRow】
// CheckBoxRow 是方框勾选（15px 小方框 + 勾号），适合「从列表里勾几个」这类
// 多选语义。设置页里的「启用 X」是**单个功能的开与关**，开关的视觉隐喻更准：
// 拨到右边 = 开，拨到左边 = 关，位置本身就承载了状态，不必再读一次文字。
//
// 【为什么不用 Material 的 Switch】
// 三个原因：
//   1) 高度 32、带 Material 的水波纹与 elevation，与这套 23px 扁平控件不搭；
//   2) 轨道颜色取自 ColorScheme，要覆盖 4 个属性才能变成主色，不如手写；
//   3) 滑块在 Flutter 里默认有 0.5 的阴影与描边，在这个配色下会显脏。
//
// 手写一个 32x16 的轨道 + 12px 圆钮，全部尺寸与颜色走 theme，与其余控件同源。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';

/// 一行「文案 + 开关」。
///
/// 整行可点（不只是开关本体）：设置页的行高有 30px，让用户必须精确点在 32x16
/// 的开关上是没必要的苛刻 —— 文字上也能点，命中区域翻了三倍。
///
/// [label] 允许为空：设置页的「滑块区 / 上号器区」把四件控件挤在一行里，开关
/// 只剩轨道没有文字。此时靠 [tooltip] 与无障碍标签说明它管什么，不能两者都空。
class SwitchRow extends StatefulWidget {
  const SwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.tooltip,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  /// 悬停提示。label 为空时用它说明这个开关管什么。
  final String? tooltip;

  @override
  State<SwitchRow> createState() => _SwitchRowState();
}

class _SwitchRowState extends State<SwitchRow> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.enabled;
    final bool value = widget.value;
    final bool highlight = enabled && _hover;
    final bool hasLabel = widget.label.isNotEmpty;

    // 没有文字标签时，tooltip 是唯一能让用户知道这个开关管什么的东西。
    final String? tip = widget.tooltip ?? (hasLabel ? widget.label : null);

    Widget body = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: enabled ? () => widget.onChanged(!value) : null,
        child: AnimatedContainer(
          duration: _down ? kPressDuration : kHoverDuration,
          curve: Curves.easeOut,
          height: kRowHeight,
          // 无文字时不留左右内边距，否则开关在行里会被挤偏。
          padding: hasLabel ? const EdgeInsets.only(right: 2) : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: highlight
                ? WorkColors.primary.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(kRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (hasLabel) ...<Widget>[
                Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: kFontBody,
                    color: enabled
                        ? WorkColors.textPrimary
                        : WorkColors.textMuted,
                    fontFamily: kFontFamily,
                    fontFamilyFallback: kFontFallback,
                  ),
                ),
                const SizedBox(width: kSwitchGap),
              ],
              SwitchTrack(value: value, enabled: enabled, hover: highlight),
            ],
          ),
        ),
      ),
    );

    // 无文字时补无障碍标签：读屏软件读到这里不能是「一个开关」而已。
    if (!hasLabel && tip != null) {
      body = Semantics(
        label: tip,
        toggled: value,
        child: body,
      );
    }
    if (tip != null) {
      body = Tooltip(message: tip, child: body);
    }
    return body;
  }
}

/// 轨道 + 圆钮。
///
/// 公开而非私有：设置页的 [_BoxedSwitch] 用「文字在上、轨道在下」的纵向排法，
/// 与 [SwitchRow] 的横向排法不同，但轨道本身必须是同一套视觉 —— 否则界面上
/// 会同时出现两种开关。
class SwitchTrack extends StatelessWidget {
  const SwitchTrack({
    super.key,
    required this.value,
    required this.enabled,
    required this.hover,
  });

  final bool value;
  final bool enabled;
  final bool hover;

  @override
  Widget build(BuildContext context) {
    final Color trackColor;
    if (!enabled) {
      trackColor = WorkColors.border;
    } else if (value) {
      // 悬停时主色再深一档，让「即将点击」有反馈；否则按下前毫无征兆。
      trackColor = hover
          ? WorkColors.primaryDark
          : WorkColors.primary;
    } else {
      trackColor = hover ? WorkColors.textHint : WorkColors.border;
    }

    return AnimatedContainer(
      duration: kStateDuration,
      curve: Curves.easeOut,
      width: kSwitchWidth,
      height: kSwitchHeight,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(kSwitchHeight / 2),
      ),
      // 圆钮用 Align 从左侧推到右侧：比 Stack + Positioned 少一层，且
      // Alignment 的过渡天然是线性的，配合 easeOut 曲线就是「滑过去」的手感。
      child: AnimatedAlign(
        duration: kStateDuration,
        curve: Curves.easeOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: kSwitchHeight - 4,
          height: kSwitchHeight - 4,
          decoration: BoxDecoration(
            color: enabled ? Colors.white : WorkColors.panel,
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
