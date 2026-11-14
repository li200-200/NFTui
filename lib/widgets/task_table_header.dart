part of 'task_table.dart';

// ---------------------------------------------------------------------------
// 表头 + 列宽抓手
//
// 【表头与数据行必须逐像素一致】
// 两者都用「SizedBox(width: widths[i]) + 1px VerticalDivider」。表头若用更宽的
// 分隔线，列就会整体右移，表头与数据行错位 —— 所以拖动的「抓手」不放在这一层，
// 而是由 [_HeaderDividerOverlay] 覆盖在上面（只覆盖表头 40px 高，不影响数据行的
// 点击）。
// ---------------------------------------------------------------------------

/// 表头行。
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.columns, required this.widths});

  final List<TaskColumn> columns;

  /// 每列的实际像素宽。与数据行用的是**同一份**数据。
  final List<double> widths;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: WorkColors.headerFill,
      child: Row(
        children: <Widget>[
          for (int i = 0; i < columns.length; i++) ...<Widget>[
            if (i > 0)
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: WorkColors.border,
              ),
            SizedBox(
              width: widths[i],
              child: Center(
                child: Padding(
                  // 与数据行同样的 6px 水平内边距：表头文字与单元格文字
                  // 在同一个居中算法下才会对齐。
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    columns[i].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: kFontTitle,
                      fontWeight: FontWeight.w600,
                      color: WorkColors.textPrimary,
                      fontFamily: kFontFamily,
                      fontFamilyFallback: kFontFallback,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 覆盖在表头上的「列宽抓手」层。
///
/// 为什么单独做一层：真正的分隔线只有 1px，鼠标几乎没法瞄准；但把可点区做宽
/// 又会占布局宽度，把表头挤得与数据行错位。所以布局保持 1px，另用一层透明
/// 覆盖物把每条线两侧各扩 4px —— 视觉不变、列对齐不变，抓手却是 9px 宽。
///
/// 只覆盖表头（高 40px）：数据行需要响应点击选中，覆盖上去会抢走那 9px 带内的
/// 点击事件。表头本身不可点，占用它对功能没有任何影响。
class _HeaderDividerOverlay extends StatelessWidget {
  const _HeaderDividerOverlay({
    required this.columns,
    required this.widths,
    required this.onDragDivider,
  });

  final List<TaskColumn> columns;
  final List<double> widths;

  /// 拖动第 index 条分隔条（第 index 列与第 index+1 列之间），参数为本次位移。
  final void Function(int index, double dx) onDragDivider;

  /// 抓手命中区总宽：1px 线 + 两侧各 4px。
  static const double _hitWidth = 9;

  @override
  Widget build(BuildContext context) {
    final List<Widget> handles = <Widget>[];
    // 第 k 条分隔线的左边缘（k 从 1 开始）= 前 k 列宽之和 + 前 k-1 条线。
    double x = 0;
    for (int k = 1; k < columns.length; k++) {
      x += widths[k - 1];
      final double lineLeft = x + (k - 1);
      final int index = k - 1;
      handles.add(
        Positioned(
          left: lineLeft - (_hitWidth - 1) / 2,
          top: 0,
          bottom: 0,
          width: _hitWidth,
          child: _DividerHandle(
            onDrag: (double dx) => onDragDivider(index, dx),
          ),
        ),
      );
    }
    return Stack(children: handles);
  }
}

/// 一条可拖动的列宽抓手（透明，只负责接收拖动）。
///
/// 线本身仍然画在 [_HeaderRow] 的 VerticalDivider 上，这里只在悬停 / 拖动时
/// 画一层高亮细条作为反馈 —— 平时完全透明，不影响表头观感。
class _DividerHandle extends StatefulWidget {
  const _DividerHandle({required this.onDrag});

  /// 本次拖动产生的水平位移（像素，可为负）。
  final void Function(double dx) onDrag;

  @override
  State<_DividerHandle> createState() => _DividerHandleState();
}

class _DividerHandleState extends State<_DividerHandle> {
  bool _hover = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 拖动中鼠标离开这条线也继续跟随（GestureDetector 自己保持手势）。
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (DragUpdateDetails d) =>
            widget.onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        child: Center(
          child: Container(
            width: (_hover || _dragging) ? 3 : 0,
            height: double.infinity,
            // 平时宽度 0（完全透明、不遮挡任何东西），悬停 / 拖动时才是主色细条。
            color: (_hover || _dragging) ? WorkColors.primary : null,
          ),
        ),
      ),
    );
  }
}
