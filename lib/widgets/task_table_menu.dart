part of 'task_table.dart';

// ---------------------------------------------------------------------------
// 右键菜单 + 空态占位
//
// 菜单的绘制与交互在 widgets/table_menu.dart（与小号表共用同一套视觉），
// 这里只负责「列出主表格有哪几项」以及把返回值翻译成父页面的回调。
// ---------------------------------------------------------------------------

/// 主表格的四项菜单。
///
/// 两个删除项都标成 danger：它们同样是破坏性操作，只是筛选条件不同 ——
/// 「删除选中」按用户勾选，「删除成功」按行的状态。分开成两项而不是合成一个
/// 带确认框的项：两者选中的依据完全不同，混在一起用户没法只删其中一类。
const List<TableMenuItem> _taskMenuItems = <TableMenuItem>[
  TableMenuItem(value: 'all', label: '全选'),
  TableMenuItem(value: 'invert', label: '反选'),
  TableMenuItem(value: 'delete', label: '删除选中', danger: true),
  TableMenuItem(value: 'deleteSucceeded', label: '删除成功', danger: true),
];

/// 弹出主表格的右键菜单，返回 'all' / 'invert' / 'delete' /
/// 'deleteSucceeded'，取消时返回 null。
Future<String?> _showTableMenu(BuildContext context, Offset position) =>
    showTableMenu(context, position, _taskMenuItems);

/// 没有任何数据时的占位。
class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.hint});

  final String hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          hint,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: kFontBody,
            color: WorkColors.textMuted,
            fontFamily: kFontFamily,
            fontFamilyFallback: kFontFallback,
          ),
        ),
      ),
    );
  }
}

