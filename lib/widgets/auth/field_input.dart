// ---------------------------------------------------------------------------
// 带前置图标的输入框
//
// 尺寸对齐参考图实测值：高 44，图标 14，提示文字 13。
//
// 校验失败的反馈方式：不弹文字提示，让输入框「边框变红 + 左右抖动两下」。
// 抖动由「false→true 边沿」或「errorTick 变化」触发 —— 后者保证「没改内容就
// 连点两次提交」也能有反馈。
// ---------------------------------------------------------------------------
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';

class FieldInput extends StatefulWidget {
  const FieldInput({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.trailing,
    this.onSubmitted,
    this.onChanged,
    this.keyboardType,
    this.hasError = false,
    this.errorTick = 0,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? trailing;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;

  /// 校验失败标记。true 时边框转红并抖两下。
  final bool hasError;

  /// 每次点提交自增。用于「同一字段连续两次失败」时重新抖动 ——
  /// 否则 hasError 恒为 true，第二次点击没有任何反馈。
  final int errorTick;

  @override
  State<FieldInput> createState() => _FieldInputState();
}

class _FieldInputState extends State<FieldInput>
    with SingleTickerProviderStateMixin {
  final FocusNode _node = FocusNode();
  bool _focused = false;

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  /// 抖动振幅（像素）
  static const double _amplitude = 6.0;

  @override
  void initState() {
    super.initState();
    _node.addListener(() {
      if (_focused != _node.hasFocus) {
        setState(() => _focused = _node.hasFocus);
      }
    });
  }

  @override
  void didUpdateWidget(covariant FieldInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 抖动的两个触发条件：
    //   1. 从「无错」变成「有错」      —— 第一次校验失败
    //   2. errorTick 变了且仍然有错    —— 没改就又点了一次提交
    // 其余情况（比如单纯 rebuild）不抖，避免不听话地乱晃。
    final bool justErrored = widget.hasError && !oldWidget.hasError;
    final bool reSubmitted =
        widget.hasError && widget.errorTick != oldWidget.errorTick;
    if (justErrored || reSubmitted) {
      _shake.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool err = widget.hasError;

    final Color borderColor;
    final double borderWidth;
    if (err) {
      borderColor = AuthColors.error;
      borderWidth = 1.4;
    } else if (_focused) {
      borderColor = AuthColors.primary;
      borderWidth = 1.0;
    } else {
      borderColor = Colors.transparent;
      borderWidth = 1.0;
    }

    final Color fill = err
        ? AuthColors.error.withValues(alpha: 0.07)
        : (_focused ? AuthColors.fieldFillFocused : AuthColors.fieldFill);

    final Color iconColor = err
        ? AuthColors.error
        : (_focused ? AuthColors.primary : AuthColors.textHint);

    // 提示文字在错误态也转红，强化反馈
    final TextStyle hintStyle = TextStyle(
      color: err
          ? AuthColors.error.withValues(alpha: 0.75)
          : AuthColors.textHint,
      fontSize: kAuthBodySize,
      fontFamily: kFontFamily,
      fontFamilyFallback: kFontFallback,
    );

    return AnimatedBuilder(
      animation: _shake,
      builder: (BuildContext context, Widget? child) {
        final double t = _shake.value;
        // 衰减正弦：4πt = 完整两个周期 → 左右各抖两下，然后自然停住
        final double dx = t > 0
            ? math.sin(t * 4 * math.pi) * _amplitude * (1 - t)
            : 0;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: kFieldHeight,
        decoration: BoxDecoration(
          color: fill,
          // 圆角刻意做小（4），和参考图一致：输入框方正，只有按钮是胶囊
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(width: 14),
            Icon(widget.icon, size: 14, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _node,
                obscureText: widget.obscure,
                keyboardType: widget.keyboardType,
                onSubmitted: widget.onSubmitted,
                // 用户一开始改错别字就把红框收掉，不用等到下次提交
                onChanged: widget.onChanged,
                style: const TextStyle(
                  fontSize: kAuthBodySize,
                  color: AuthColors.textPrimary,
                  fontFamily: kFontFamily,
                  fontFamilyFallback: kFontFallback,
                ),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: hintStyle,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (widget.trailing != null) ...<Widget>[
              widget.trailing!,
              const SizedBox(width: 10),
            ] else
              const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }
}
