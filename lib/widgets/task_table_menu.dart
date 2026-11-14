part of 'task_table.dart';

// ---------------------------------------------------------------------------
// 右键菜单 + 空态占位
//
// 菜单只负责「弹出并返回用户选了哪一项」，动作由父页面执行 —— 本组件不自己
// 决定删哪些行。
// ---------------------------------------------------------------------------

/// 弹出表格的右键菜单，返回用户选择的项（'all' / 'invert' / 'delete' /
/// 'deleteSucceeded'），取消时返回 null。
Future<String?> _showTableMenu(BuildContext context, Offset position) {
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
      const PopupMenuItem<String>(
        value: 'all',
        height: 34,
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: _MenuRow(label: '全选', color: WorkColors.textPrimary),
      ),
      const PopupMenuItem<String>(
        value: 'invert',
        height: 34,
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: _MenuRow(label: '反选', color: WorkColors.textPrimary),
      ),
      // 两个删除项都用 danger 色：它们同样是破坏性操作，只是筛选条件不同 ——
      // 「删除选中」按用户勾选，「删除成功」按行的状态（status == succeeded）。
      // 分开成两项而不是合成一个带确认框的项：两者选中的依据完全不同，
      // 混在一起用户没法只删其中一类。
      const PopupMenuItem<String>(
        value: 'delete',
        height: 34,
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: _MenuRow(label: '删除选中', color: WorkColors.danger),
      ),
      const PopupMenuItem<String>(
        value: 'deleteSucceeded',
        height: 34,
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: _MenuRow(label: '删除成功', color: WorkColors.danger),
      ),
    ],
  );
}

/// 右键菜单的一行。
///
/// 主题里把 hoverColor 设成了透明（为了全局去掉 Material 的水波纹），
/// PopupMenuItem 自带的悬停高亮因此也一起没了。这里自己补一层：
/// 悬停时垫主色浅底 + 圆角，鼠标在哪一项上一目了然。
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

