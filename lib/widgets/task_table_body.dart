part of 'task_table.dart';

// ---------------------------------------------------------------------------
// 滚动体 + 数据行 + 单元格画法
// ---------------------------------------------------------------------------

/// 滚动体：**自己持有** ScrollController。
///
/// 早先 controller 由父组件在 build() 里现造一个传进来，于是每帧 rebuild 都换
/// 一个新实例，带来三个问题：
///   1) 旧实例无人 dispose（ChangeNotifier 泄漏）；
///   2) dispose 里释放的是「父组件这一帧刚造的那个」，所有权错位；
///   3) Scrollable 检测到 controller 实例变了会重建 ScrollPosition，滚动偏移
///      归零 —— 父页面每次 setState，用户往下翻的表格就被弹回顶部。
/// 放进 State 后：实例在整个生命周期内稳定，且由持有者负责释放。
class _ScrollableBody extends StatefulWidget {
  const _ScrollableBody({
    required this.columns,
    required this.rows,
    required this.selected,
    required this.onToggleSelection,
    required this.enabled,
    required this.widths,
    this.onDisabledTap,
  });

  final List<TaskColumn> columns;
  final List<TaskRow> rows;
  final Set<int> selected;
  final ValueChanged<int> onToggleSelection;
  final bool enabled;

  /// 禁用态下点击某一行的回调：给「点了没反应」一个解释。
  final ValueChanged<String>? onDisabledTap;

  /// 每列的实际像素宽（由 TaskTable 的 State 持有并驱动）。
  final List<double> widths;

  @override
  State<_ScrollableBody> createState() => _ScrollableBodyState();
}

class _ScrollableBodyState extends State<_ScrollableBody> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      thickness: kScrollThickness,
      radius: const Radius.circular(kScrollRadius),
      child: ListView.builder(
        controller: _controller,
        padding: EdgeInsets.zero,
        itemCount: widget.rows.length,
        itemExtent: kRowItemExtent,
        itemBuilder: (BuildContext context, int i) {
          return _DataRow(
            columns: widget.columns,
            row: widget.rows[i],
            striped: i.isOdd,
            last: i == widget.rows.length - 1,
            selected: widget.selected.contains(i),
            /* 禁用时不再给 null（那样点了毫无反应，用户以为卡死），
               改成弹一条说明；没有回调时仍退回静默。 */
            onTap: widget.enabled
                ? () => widget.onToggleSelection(i)
                : (widget.onDisabledTap == null
                      ? null
                      : () => widget.onDisabledTap!('运行中不可修改列表，请先「结束」')),
            widths: widget.widths,
          );
        },
      ),
    );
  }
}

class _DataRow extends StatefulWidget {
  const _DataRow({
    required this.columns,
    required this.row,
    required this.striped,
    required this.last,
    required this.selected,
    required this.onTap,
    required this.widths,
  });

  final List<TaskColumn> columns;
  final TaskRow row;
  final bool striped;
  final bool last;
  final bool selected;

  /// 每列的实际像素宽 —— 必须与表头用的是**同一份**数据，
  /// 否则拖动之后表头与数据行会错位。
  final List<double> widths;

  /// 点击整行：切换选中态。禁用时为 null。
  final VoidCallback? onTap;

  @override
  State<_DataRow> createState() => _DataRowState();
}

class _DataRowState extends State<_DataRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool selected = widget.selected;
    final Color base = selected
        ? WorkColors.primarySoft
        : (widget.striped ? WorkColors.rowAlt : WorkColors.fieldFill);
    // 悬停再加深一档：选中行更明显，未选中行给一点「可点」的反馈。
    final Color background = (_hover && widget.onTap != null)
        ? (selected
              ? WorkColors.primary.withValues(alpha: 0.22)
              : WorkColors.primary.withValues(alpha: 0.07))
        : base;

    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: kHoverDuration,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: background,
            // 最后一行不加下边框：表格外框已经有一条 1px 线，再画一条就是 2px。
            border: widget.last
                ? null
                : const Border(
                    bottom: BorderSide(color: WorkColors.border, width: 1),
                  ),
          ),
          // 选中行左侧一条主色竖条，比整行浅底更好认。
          // 用 foregroundDecoration 而不是子节点：子节点会挤占行内宽度，
          // 让所有列宽整体右移 3px，拖动后就与表头错位了。
          foregroundDecoration: selected
              ? const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: WorkColors.primary, width: 3),
                  ),
                )
              : null,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < widget.columns.length; i++) ...<Widget>[
                if (i > 0)
                  // 数据行的分隔线只做视觉，不参与拖动（抓手在表头上，
                  // 位置与这里严格对齐：两边的宽度来自同一份 widths）。
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: WorkColors.border,
                  ),
                SizedBox(
                  width: widget.widths[i],
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: _cell(widget.columns[i]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 按列定义决定这一格怎么画：
  ///   · 状态列 → 彩色小圆点 + 文字（颜色来自 [TaskStatus.color]）；
  ///   · 内容不可控的列（tooltip = true）→ 省略号 + tooltip；
  ///   · 其余列 → 纯文字。
  Widget _cell(TaskColumn column) {
    final String text = widget.row.value(column.field);

    if (column.field == TaskField.status) {
      final Color dotColor = widget.row.status.color;
      /* 圆点 + 间隙是 12px 固定宽度，文字用 Flexible 收缩。
       *
       * 【为什么外面还要套 LayoutBuilder】
       * 单元格被压到 12px 以下时（窗口极窄 / 列被拖到极限），圆点+间隙自己就
       * 已经放不下了，Flexible 只能缩文字、缩不了这两个固定宽的兄弟 ——
       * 于是 RenderFlex 溢出，屏幕上出现黄黑警示条。实测在 400 宽窗口下溢出
       * 7.5px。
       *
       * 这里按实际可用宽度降级：够 24px 才画圆点，否则只画文字。窗口最小宽
       * 880 时永远走不到这条分支，但列宽算法在极端输入下会放弃约束（见
       * task_table_widths.dart 的说明），所以必须兜住。 */
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final bool showDot = c.maxWidth >= 24;
          final Widget label = Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: kFontBody,
              color: dotColor,
              fontFamily: kFontFamily,
              fontFamilyFallback: kFontFallback,
            ),
          );
          if (!showDot) {
            return Align(
              alignment: Alignment.centerLeft,
              child: label,
            );
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Flexible(child: label),
            ],
          );
        },
      );
    }

    final Widget label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: kFontBody,
        color: WorkColors.textPrimary,
        fontFamily: kFontFamily,
        fontFamilyFallback: kFontFallback,
      ),
    );

    // 空值不挂 tooltip：悬停弹出一个空框比不弹更让人困惑。
    if (column.tooltip && text.trim().isNotEmpty) {
      return Tooltip(message: text, child: label);
    }
    return label;
  }
}
