// ---------------------------------------------------------------------------
// 带左标签的输入框：「[标签格][输入格]」紧贴两格
//
// 这是本 UI 的签名控件，来自 .ui 里 QLabel + QLineEdit 并排的写法：
// 左边一格固定宽（60 / 51 / 41），右边一格吃掉剩余宽度，两者之间只有 1px 边框
// 相隔，圆角只给整块的外侧两角 —— 合起来像一个两段式控件。
//
// 【FocusNode 归本组件所有】
// 聚焦态只影响这一格自己的边框与外发光，所以监听器里只 setState 自己，
// 不往上抛回调 —— 否则输入框一聚焦就要重建整个页面（含三张表）。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';

class LabeledField extends StatefulWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.hint = '',
    this.labelWidth = kLabelWidth,
    this.obscure = false,
    this.keyboardType,
    this.onSubmitted,
    this.onChanged,
    this.trailing,
    this.enabled = true,
    this.hasError = false,
  });

  /// 左侧标签文案（「账户」「密码」「藏品Id」…）。
  final String label;

  final TextEditingController controller;

  /// 空值提示。取自 .ui 的 placeholderText。
  final String hint;

  /// 左侧标签格宽度。默认取 [kLabelWidth]（60），左栏所有标签格统一这一个值，
  /// 各输入框的左边界才会落在同一条竖线上。
  ///
  /// 只有宽度确实需要不同的场合（比如将来在窄容器里复用）才传别的值；
  /// 工作台内不要逐处传不同的数 —— 那正是「支付密码格比账户格宽」的来源。
  final double labelWidth;

  /// 密码框（.ui 里 echoMode = Password）。
  final bool obscure;

  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  /// 输入框右侧的附加控件（本任务里是「查询」小按钮）。
  final Widget? trailing;

  final bool enabled;

  /// 校验失败：边框转红并加粗。
  final bool hasError;

  @override
  State<LabeledField> createState() => _LabeledFieldState();
}

class _LabeledFieldState extends State<LabeledField> {
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
    final Color borderColor = widget.hasError
        ? WorkColors.error
        : (focused ? WorkColors.primary : WorkColors.border);
    final double borderWidth = (widget.hasError || focused) ? 1.4 : 1.0;

    return SizedBox(
      height: kRowHeight,
      child: Row(
        // stretch：两格等高，标签格的底纹才会与输入格严丝合缝。
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ---- 左标签格 ----
          Container(
            width: widget.labelWidth,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: WorkColors.panel,
              border: Border.all(color: WorkColors.border, width: 1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(kRadius),
                bottomLeft: Radius.circular(kRadius),
              ),
            ),
            child: Padding(
              // 标签格的内边距压到 0：.ui 里「支付密码」「藏品信息」这类四字标签
              // 在 51 宽的格子里只剩 49px 可用（左右边框各 1px），12.5 号中文
              // 四字约 50px —— 任何水平内边距都会把它挤成省略号。
              padding: EdgeInsets.zero,
              child: FittedBox(
                // 差 1px 时按比例缩到 0.98 而不是截断：四字标签被截成「支付密…」
                // 是明显的信息丢失，而 0.98 的缩放肉眼看不出来。
                fit: BoxFit.scaleDown,
                child: Text(
                  widget.label,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: kFontBody,
                    color: WorkColors.textPrimary,
                    fontFamily: kFontFamily,
                    fontFamilyFallback: kFontFallback,
                  ),
                ),
              ),
            ),
          ),
          // ---- 右输入格 ----
          Expanded(
            child: AnimatedContainer(
              duration: kHoverDuration,
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: !widget.enabled
                    ? WorkColors.panel
                    : (focused
                          ? WorkColors.fieldFillFocused
                          : WorkColors.fieldFill),
                border: Border.all(color: borderColor, width: borderWidth),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(kRadius),
                  bottomRight: Radius.circular(kRadius),
                ),
                // 聚焦时给一层很浅的主色外发光：边框变色的同时有「浮起来」的
                // 感觉。spreadRadius 0.5 是为了让 1px 边框外侧也带一点光，
                // 否则光晕被边框挡住看不见。
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
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _node,
                      enabled: widget.enabled,
                      obscureText: widget.obscure,
                      keyboardType: widget.keyboardType,
                      onSubmitted: widget.onSubmitted,
                      onChanged: widget.onChanged,
                      // 光标高度按字号自动算，显式给一个与行高协调的值，
                      // 免得在 30 高的格子里光标顶到上下边框。
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
                        // 边框与底色都由外层 AnimatedContainer 画，
                        // 这里必须全部清掉，否则会出现双层边框。
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (widget.trailing != null) ...<Widget>[
                    widget.trailing!,
                    const SizedBox(width: 6),
                  ] else
                    const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
