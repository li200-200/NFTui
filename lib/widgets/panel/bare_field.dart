// ---------------------------------------------------------------------------
// 无标签输入框（对应 .ui 里「不配 QLabel、独占整行」的 QLineEdit）
//
// 目前唯一的用处是 untitled.ui 的 `lineEdit_cpxx_2`：整行 181 宽、placeholder 为
// `key`、alignment = AlignCenter、enabled = false。它没有配对的 QLabel（其余六行
// 都是「标签格 + 输入格」），而是自己占满整行，所以不能硬塞进 LabeledField 的
// 两格结构。
//
// 【为什么独立成一个公共控件】
// 早先它是 main_page.dart 里的私有 `_BareField`。设置页的通知区（lineEdit_tz）
// 也需要「没有标签、自己占一格」的输入框，私有类跨不了文件 —— 与其复制一份，
// 不如提上来共用。两者视觉完全一致：1px 边框、4px 圆角、聚焦外发光。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';

class BareField extends StatefulWidget {
  const BareField({
    super.key,
    required this.controller,
    this.hint = '',
    this.enabled = true,
    this.center = true,
    this.onChanged,
  });

  final TextEditingController controller;

  /// 空值提示（.ui 的 placeholderText）。
  final String hint;

  final bool enabled;

  /// 文字是否居中。.ui 里 lineEdit_cpxx_2 是 AlignCenter，其余输入框是左对齐。
  final bool center;

  final ValueChanged<String>? onChanged;

  @override
  State<BareField> createState() => _BareFieldState();
}

class _BareFieldState extends State<BareField> {
  final FocusNode _node = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (_focused != _node.hasFocus) {
      setState(() => _focused = _node.hasFocus);
    }
  }

  @override
  void dispose() {
    // 先摘监听再释放：dispose 期间 FocusNode 还会发一次「失去焦点」通知，
    // 那时如果回调还在，就会对已经 unmount 的 State 调 setState。
    _node.removeListener(_onFocusChanged);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool focused = _focused && widget.enabled;
    final Color borderColor =
        focused ? WorkColors.primary : WorkColors.border;
    final double borderWidth = focused ? 1.4 : 1.0;

    return AnimatedContainer(
      duration: kHoverDuration,
      curve: Curves.easeOut,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: !widget.enabled
            ? WorkColors.panel
            : (focused ? WorkColors.fieldFillFocused : WorkColors.fieldFill),
        border: Border.all(color: borderColor, width: borderWidth),
        // 独立一格，四角全圆 —— 没有相邻的标签格要接缝。
        borderRadius: BorderRadius.circular(kRadius),
        // 与 LabeledField 同一套聚焦外发光，两处输入框的交互语言一致。
        boxShadow: focused
            ? <BoxShadow>[
                BoxShadow(
                  color: WorkColors.primary.withValues(alpha: 0.12),
                  blurRadius: 6,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _node,
        enabled: widget.enabled,
        onChanged: widget.onChanged,
        // .ui 里 lineEdit_cpxx_2 的 alignment = Qt::AlignCenter，文字居中。
        textAlign: widget.center ? TextAlign.center : TextAlign.start,
        cursorHeight: 15,
        style: const TextStyle(
          fontSize: kFontBody,
          color: WorkColors.textPrimary,
          fontFamily: kFontFamily,
          fontFamilyFallback: kFontFallback,
        ),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: const TextStyle(
            fontSize: kFontHint,
            color: WorkColors.textMuted,
            fontFamily: kFontFamily,
            fontFamilyFallback: kFontFallback,
          ),
          // 边框与底色由外层 AnimatedContainer 画，这里必须清掉，否则双层边框。
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
