// ---------------------------------------------------------------------------
// 胶囊主按钮
//
// 实测 160x40，圆角 = 高度一半（kPillRadius）。用于「登录 / 注册 / 提交数据」
// 这类页面主操作。
//
// 【为什么是胶囊而不是工作台的方角按钮】
// 验证页整体是「圆润」的：输入框圆角 4、勾选框圆角 3、按钮全圆。工作台是
// 工具界面，全部方角。这是两套视觉语言，不要互相借。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';

class PillButton extends StatefulWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.width = 160,
    this.height = 40,
    this.loading = false,
    this.icon,
  });

  final String label;

  /// 为 null 表示禁用（不响应悬停与按下）。
  final VoidCallback? onPressed;

  /// 实测按钮 160x40。充值页的「提交数据」用 170。
  final double width;
  final double height;

  /// 提交中：文字换成转圈，并自动禁用（避免重复提交）。
  final bool loading;

  /// 可选的前置图标。
  final IconData? icon;

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onPressed != null && !widget.loading;

    // 四态配色：禁用 / 按下 / 悬停 / 常态。
    // 禁用用主色 45% 透明而不是灰色：按钮位置与形状不变，只变深浅，
    // 用户能看出「这里本来有个按钮，现在点不了」。
    final Color bg;
    if (!enabled) {
      bg = AuthColors.primary.withValues(alpha: 0.45);
    } else if (_down) {
      bg = AuthColors.primaryDark;
    } else if (_hover) {
      bg = AuthColors.primaryAlt;
    } else {
      bg = AuthColors.primary;
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(widget.height / 2),
          ),
          alignment: Alignment.center,
          child: widget.loading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (widget.icon != null) ...<Widget>[
                      Icon(widget.icon, size: 15, color: Colors.white),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        fontFamily: kFontFamily,
                        fontFamilyFallback: kFontFallback,
                        // 字距 1.5：两个字的「登录」居中时不会显得挤在一起。
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
