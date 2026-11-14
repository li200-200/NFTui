// ---------------------------------------------------------------------------
// 面板按钮（发送 / 登录 / 查询 / 加入修改）
//
// 配色逻辑：
//   · primary = true  → 主色描边 + 主色文字（「登录」这种主操作）
//   · accentColor     → 自定义强调色
//   · 都不传          → 次级灰（textHint）
// 禁用时底色退成面板灰、文字变辅助色，且不响应悬停 / 按下 —— 这是「发送」
// 在未登录时的样子（.ui 里那个 enabled=false 的 QPushButton）。
//
// 【为什么用 GestureDetector 而不是按钮类】
// Material 的按钮自带水波纹与最小点击区，两者都要额外压制；这套 UI 是扁平的
// Win32 观感，按下态只是底色加深一档，直接手写更快也更准。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';

class PanelButton extends StatefulWidget {
  const PanelButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.accentColor,
    this.height = kRowHeight,
  });

  final String label;

  /// null = 禁用。用「回调是否为 null」表达禁用态，与 Flutter 惯例一致，
  /// 调用方不必再多传一个 enabled 参数（两个来源一定会有一天不同步）。
  final VoidCallback? onPressed;

  /// true 时用主色描边 + 主色文字，且文字加粗（主操作）。
  final bool primary;

  /// 自定义强调色（描边 / 文字 / 悬停底色）。为空时沿用 [primary] 的默认配色。
  final Color? accentColor;

  final double height;

  @override
  State<PanelButton> createState() => _PanelButtonState();
}

class _PanelButtonState extends State<PanelButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onPressed != null;

    final Color accent =
        widget.accentColor ??
        (widget.primary ? WorkColors.primary : WorkColors.textHint);

    final Color bg;
    if (!enabled) {
      bg = WorkColors.panel;
    } else if (_down) {
      bg = accent.withValues(alpha: 0.20);
    } else if (_hover) {
      bg = accent.withValues(alpha: 0.12);
    } else {
      bg = WorkColors.fieldFill;
    }

    final Color fg = !enabled ? WorkColors.textMuted : accent;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) {
        // 鼠标在按下状态下移出：把按下态一起清掉，否则按钮会「卡在按下色」。
        setState(() {
          _hover = false;
          _down = false;
        });
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          /* 【时长为什么按下比悬停短】
           * 悬停 90ms 是从容的「渐显」，按下 60ms 是「立刻有回应」。两者用同一个
           * 时长会有一头不对：都取 90 则按下发黏，都取 60 则悬停像闪。
           * 这是按钮手感最关键的一处细节。 */
          duration: _down ? kPressDuration : kHoverDuration,
          curve: Curves.easeOut,
          height: widget.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(
              color: enabled
                  ? accent.withValues(alpha: _down ? 0.75 : 0.55)
                  : WorkColors.border,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(kRadius),
            // 悬停时轻微抬起；按下时阴影消失，形成「按下去」的手感。
            boxShadow: (enabled && _hover && !_down)
                ? <BoxShadow>[
                    BoxShadow(
                      color: accent.withValues(alpha: 0.18),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: kFontBody,
              fontWeight: widget.primary ? FontWeight.w600 : FontWeight.w400,
              color: fg,
              fontFamily: kFontFamily,
              fontFamilyFallback: kFontFallback,
            ),
          ),
        ),
      ),
    );
  }
}
