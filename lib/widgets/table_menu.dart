// ---------------------------------------------------------------------------
// 表格右键菜单（主表格与小号表共用）
//
// 【为什么提成公用组件】
// 「运行中的任务」和「设置页的小号表」都要右键出菜单，两处菜单必须长得一模一样
// （同样的高度、圆角、悬停底色、字号）—— 各写一份迟早会漂移。这里只保留
// 「弹出菜单 + 返回用户选了哪一项」这件事，动作由调用方执行：
// 组件不自己决定删哪些行。
//
// 【为什么不用 showMenu 的默认样式】
// 主题里把 hoverColor 设成了透明（为了全局去掉 Material 水波纹），
// PopupMenuItem 自带的悬停高亮因此也没了。所以每一项自己画一层悬停底色，
// 否则鼠标在哪一项上看不出来。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';

/// 菜单项定义。
///
/// [value] 是回传给调用方的标识（不要用下标 —— 菜单项顺序调整时下标会变，
/// 而字符串常量不会）。[danger] 为真时用红色，标记破坏性操作。
class TableMenuItem {
  const TableMenuItem({
    required this.value,
    required this.label,
    this.danger = false,
  });

  final String value;
  final String label;
  final bool danger;
}

/// 弹出表格右键菜单，返回用户选择的 [TableMenuItem.value]；取消时返回 null。
///
/// [position] 是**全局**坐标（`event.position`），showMenu 内部会自己换算。
Future<String?> showTableMenu(
  BuildContext context,
  Offset position,
  List<TableMenuItem> items,
) {
  final RelativeRect rect = RelativeRect.fromLTRB(
    position.dx,
    position.dy,
    position.dx,
    position.dy,
  );
  return showMenu<String>(
    context: context,
    position: rect,
    // 默认 300ms 的展开动画在桌面右键里显得拖沓。展开用 kStateDuration（150ms，
    // 让用户看清菜单从哪弹出），收起用 kHoverDuration（90ms，选了就快点消失）。
    popUpAnimationStyle: const AnimationStyle(
      duration: kStateDuration,
      reverseDuration: kHoverDuration,
    ),
    color: WorkColors.fieldFill,
    elevation: 6,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: const BorderSide(color: WorkColors.border, width: 1),
    ),
    items: <PopupMenuEntry<String>>[
      for (final TableMenuItem item in items)
        PopupMenuItem<String>(
          value: item.value,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _MenuRow(
            label: item.label,
            color: item.danger ? WorkColors.danger : WorkColors.textPrimary,
          ),
        ),
    ],
  );
}

/// 右键菜单的一行，自带悬停底色（见文件头说明）。
class _MenuRow extends StatefulWidget {
  const _MenuRow({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: kHoverDuration,
        curve: Curves.easeOut,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: _hover
              ? WorkColors.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(kRadius),
        ),
        child: Text(
          widget.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: kFontBody,
            color: widget.color,
            fontFamily: kFontFamily,
            fontFamilyFallback: kFontFallback,
          ),
        ),
      ),
    );
  }
}
