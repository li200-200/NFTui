// ---------------------------------------------------------------------------
// 面板下拉选择（「功能」「方式」「支付」以及信息区顶部那个空列表）
//
// 收起态只显示纯文本（selectedItemBuilder）：勾选标记只在展开后的菜单里出现，
// 否则闭合的窄框里会凭空少一截宽度 —— 41 宽的标签格 + 212 宽的面板，
// 少 16px 足以让「提取支付链接」被省略号切掉。
//
// 展开后的下拉项由 [_DropdownItemRow] 画：悬停垫主色浅底、选中项打勾并加粗。
// 主题里 hoverColor 被设成透明（全局去水波纹），DropdownMenuItem 自带的悬停
// 高亮也就没了，所以必须自己画一层，保证「鼠标停在哪 / 选了哪」都看得见。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';

class PanelDropdown extends StatefulWidget {
  const PanelDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint = '',
    this.borderRadius,
  });

  /// 当前选中项。必须恰好存在于 [items] 中，否则 DropdownButton 会断言失败
  /// （调用方在过滤 items 时要负责把它回落成 null）。
  final String? value;

  final List<String> items;

  /// null = 禁用。
  final ValueChanged<String?>? onChanged;

  /// 空列表时的提示文案。
  final String hint;

  /// 四角圆角。默认 3（独立使用时四角都圆）。
  ///
  /// 「标签格 + 下拉」并排时由调用方传入只圆右侧两角 —— 与 LabeledField 的
  /// 两格语言一致：左格只圆左边两角，右格只圆右边两角，中间共用 1px 边框。
  /// 若两边都给全圆角，接缝处会出现 2px 双线。
  final BorderRadius? borderRadius;

  @override
  State<PanelDropdown> createState() => _PanelDropdownState();
}

class _PanelDropdownState extends State<PanelDropdown> {
  bool _hover = false;

  static const TextStyle _itemStyle = TextStyle(
    fontSize: kFontBody,
    color: WorkColors.textPrimary,
    fontFamily: kFontFamily,
    fontFamilyFallback: kFontFallback,
  );

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onChanged != null;
    final bool active = enabled && _hover;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: kHoverDuration,
          curve: Curves.easeOut,
        height: kRowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: active ? WorkColors.fieldFillFocused : WorkColors.fieldFill,
          border: Border.all(
            color: active
                ? WorkColors.primary.withValues(alpha: 0.75)
                : WorkColors.border,
            width: active ? 1.4 : 1,
          ),
          borderRadius: widget.borderRadius ?? BorderRadius.circular(kRadius),
          // 悬停时与输入框聚焦一致的浅色外发光，交互语言统一。
          boxShadow: active
              ? <BoxShadow>[
                  BoxShadow(
                    color: WorkColors.primary.withValues(alpha: 0.10),
                    blurRadius: 5,
                  ),
                ]
              : null,
        ),
        child: DropdownButton<String>(
          value: widget.value,
          isExpanded: true,
          hint: Text(
            widget.hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: kFontHint,
              color: WorkColors.textMuted,
              fontFamily: kFontFamily,
              fontFamilyFallback: kFontFallback,
            ),
          ),
          // Material 默认在文字下面画一条下划线，这里必须去掉：
          // 边框已经由外层容器画好了。
          underline: const SizedBox.shrink(),
          icon: AnimatedRotation(
            // 悬停时箭头转 180°，暗示「点开就是这一层」。
            turns: active ? 0.5 : 0,
            duration: kStateDuration,
          curve: Curves.easeOut,
            child: Icon(
              Icons.expand_more,
              size: 16,
              color: active ? WorkColors.primary : WorkColors.textHint,
            ),
          ),
          style: _itemStyle,
          dropdownColor: WorkColors.fieldFill,
          borderRadius: BorderRadius.circular(4),
          menuMaxHeight: 260,
          // 收起态只显示纯文本，见文件头的说明。
          selectedItemBuilder: (BuildContext context) => widget.items
              .map(
                (String s) => Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    s,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _itemStyle,
                  ),
                ),
              )
              .toList(),
          items: widget.items.map((String s) {
            return DropdownMenuItem<String>(
              value: s,
              child: _DropdownItemRow(text: s, selected: s == widget.value),
            );
          }).toList(),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}

/// 展开后的下拉项：悬停垫主色浅底、选中项打勾并加粗。
class _DropdownItemRow extends StatefulWidget {
  const _DropdownItemRow({required this.text, required this.selected});

  final String text;
  final bool selected;

  @override
  State<_DropdownItemRow> createState() => _DropdownItemRowState();
}

class _DropdownItemRowState extends State<_DropdownItemRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool selected = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: kHoverDuration,
            curve: Curves.easeOut,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: _hover
              ? WorkColors.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(kRadius),
        ),
        child: Row(
          children: <Widget>[
            // 固定宽度的勾选槽：有选中 / 没选中都占位，文字不会左右跳动。
            SizedBox(
              width: 16,
              child: selected
                  ? const Icon(Icons.check, size: 13, color: WorkColors.primary)
                  : null,
            ),
            Expanded(
              child: Text(
                widget.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: kFontBody,
                  color: selected ? WorkColors.primary : WorkColors.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  fontFamily: kFontFamily,
                  fontFamilyFallback: kFontFallback,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
