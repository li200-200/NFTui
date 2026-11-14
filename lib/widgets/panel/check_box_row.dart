// ---------------------------------------------------------------------------
// 方框勾选（「启用定时」「qd模式」这类）
//
// 与验证页的胶囊勾选是两个不同组件：这里是工作台的小号方框（15px），
// 悬停时整行垫一层极浅的主色 —— 鼠标落在文字上也能感知「这一整行可点」，
// 而不是只有 15px 的方框能点中。
//
// 本任务的 .ui 里没有勾选项，但这个组件是工作台控件库的一部分：左栏「选项区」
// 后续要加开关时直接用，不必再写一个。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';

class CheckBoxRow extends StatefulWidget {
  const CheckBoxRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  State<CheckBoxRow> createState() => _CheckBoxRowState();
}

class _CheckBoxRowState extends State<CheckBoxRow> {
  /// 方框边长。15 是这套 UI 的固定值：再大方框会与 12.5 号文字不成比例，
  /// 再小则勾号（11px）画不下。
  static const double _box = 15;

  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.enabled;
    final bool value = widget.value;
    final bool highlight = enabled && _hover;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => widget.onChanged(!value) : null,
        child: AnimatedContainer(
          duration: kStateDuration,
          curve: Curves.easeOut,
          height: kRowHeight,
          decoration: BoxDecoration(
            color: highlight
                ? WorkColors.primary.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(kRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedContainer(
                duration: kStateDuration,
          curve: Curves.easeOut,
                width: _box,
                height: _box,
                decoration: BoxDecoration(
                  color: value
                      ? WorkColors.primary
                      : (highlight
                            ? WorkColors.fieldFillFocused
                            : WorkColors.fieldFill),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: value
                        ? WorkColors.primary
                        : (highlight
                              ? WorkColors.primary
                              : WorkColors.textHint),
                    width: 1.2,
                  ),
                  // 选中时一点点投影，让方框从浅色面板上「立」起来。
                  boxShadow: value
                      ? <BoxShadow>[
                          BoxShadow(
                            color: WorkColors.primary.withValues(alpha: 0.22),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: value
                    ? const Icon(Icons.check, size: 11, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 6),
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
            ],
          ),
        ),
      ),
    );
  }
}
