// ---------------------------------------------------------------------------
// 工作台右侧任务表格（.ui 里的三个 QTableWidget 共用一个组件）
//
// 三张表的区别只有列定义（kRunColumns / kOrderColumns / kDoneColumns），
// 布局、列宽拖动、选中态、右键菜单全部共用 —— 否则三份代码一定会各自漂移，
// 最典型的就是「完成」表的表头与数据行差 1px。
//
// ---------------------------------------------------------------------------
// 【文件结构】
//
// 本文件只留「状态 + 布局编排 + 列宽拖动裁决」。视觉组件拆成三个 part：
//
//   part  task_table_header.dart   表头行 + 列宽抓手 + 拖动手感
//   part  task_table_body.dart     滚动体 + 数据行 + 单元格画法
//   part  task_table_menu.dart     右键菜单项 + 空态占位
//
// 列宽算法在 task_table_widths.dart（纯 Dart 函数，可脱离 Flutter 单测）。
//
// 【列宽状态为什么必须留在本组件】
// 宽度由本组件自己持有（_widths）。父页面切 Tab、点按钮、刷新数据都会重建，
// 如果列宽放在父页面，每次重建都会重新按 flex 分配，用户刚拖好的宽度立刻弹回。
// 这是「拖完列宽切个 Tab 就白拖了」这类 bug 的唯一根治办法。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/models.dart';
import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/table_menu.dart';
import 'package:app_ui/widgets/task_table_widths.dart';

part 'task_table_body.dart';
part 'task_table_header.dart';
part 'task_table_menu.dart';

/// 工作台右侧任务表格。
class TaskTable extends StatefulWidget {
  const TaskTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.selected,
    required this.onToggleSelection,
    required this.onSelectAll,
    required this.onInvertSelection,
    required this.onDeleteSelected,
    required this.onDeleteSucceeded,
    this.enabled = true,
    this.onDisabledTap,
    this.emptyHint = '暂无数据（右键可全选 / 反选 / 删除选中 / 删除成功）',
  });

  /// 列定义。三张表靠它区分。
  final List<TaskColumn> columns;

  final List<TaskRow> rows;

  /// 被选中行的下标集合（由父页面持有，便于「删除选中」时直接删行）。
  final Set<int> selected;

  /// 点击某一行：切换它的选中态。
  final ValueChanged<int> onToggleSelection;

  /// 右键菜单：全选。
  final VoidCallback onSelectAll;

  /// 右键菜单：反选。
  final VoidCallback onInvertSelection;

  /// 右键菜单：删除选中。
  final VoidCallback onDeleteSelected;

  /// 右键菜单：删除成功（清掉状态为「成功」的行）。
  final VoidCallback onDeleteSucceeded;

  /// 运行中禁用右键菜单与行选中（只读）。
  final bool enabled;

  /// 禁用态下用户点表格 / 右键时的回调。
  ///
  /// 用来给「点了没反应」一个明确解释。为 null 时保持静默 —— 组件本身不该
  /// 强制调用方实现提示。
  final ValueChanged<String>? onDisabledTap;

  /// 空表时的占位文案。
  final String emptyHint;

  @override
  State<TaskTable> createState() => _TaskTableState();
}

/// 一次「宽度解析」的结果：应该用哪份宽度、以及是否需要提交到 State。
class _WidthPlan {
  const _WidthPlan(this.widths, this.changed);

  final List<double> widths;
  final bool changed;
}

class _TaskTableState extends State<TaskTable> {
  /// 每列的实际宽度（像素）。null = 还没测量过，按 flex 等比分配。
  ///
  /// 只在「用户拖过分隔条」或「窗口宽度变了」时才重算：
  ///   · 首次布局：按 columns[i].flex 等比切开可用宽度；
  ///   · 用户拖动：只改被拖那一列与其右邻列，其余列纹丝不动；
  ///   · 窗口变化：把当前宽度按比例缩放，保持用户调好的相对关系。
  List<double>? _widths;

  /// 上一次布局时的可用宽度（表格内容区，不含边框与竖向分隔条）。
  double _lastAvail = 0;

  /// 待提交的宽度（见 build 里 _resolveWidths 的说明）。
  List<double>? _pendingWidths;
  double _pendingAvail = 0;

  /// 纯函数式：只读 [_widths] / [_lastAvail]，绝不写它们。
  ///
  /// 这样 LayoutBuilder 在同一帧里被调用多次时结果完全一致 —— 否则第二遍会拿
  /// 第一遍已经 rescale 过的宽度再 rescale 一次，窗口每变一次宽，列宽就整体
  /// 缩小一点（越缩越窄）。
  _WidthPlan _resolveWidths(double avail) {
    final List<double>? cur = _widths;
    if (cur == null) {
      return _WidthPlan(initialWidths(widget.columns, avail), true);
    }
    if ((avail - _lastAvail).abs() <= 0.5) {
      return _WidthPlan(cur, false);
    }
    // 窗口宽度变了：按比例缩放，保留用户的调整结果。
    return _WidthPlan(
      rescaleWidths(widget.columns, cur, _lastAvail, avail),
      true,
    );
  }

  /// 拖动第 [index] 条分隔条（即第 index 列与第 index+1 列之间）[dx] 像素。
  ///
  /// 夹取规则与「只动相邻两列」的约束都在 [dragDivider] 里，这里只做提交。
  void _dragDivider(int index, double dx) {
    final List<double>? cur = _widths;
    if (cur == null) {
      return;
    }
    final List<double> next = dragDivider(widget.columns, cur, index, dx);
    if (widthsClose(cur, next)) {
      return;
    }
    setState(() => _widths = next);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 内容区宽度 = 表格总宽 - 左右边框(2px) - 竖向分隔条。
        final double avail = availableWidth(widget.columns, constraints.maxWidth);
        /* 【build 里不能直接改 State 字段并依赖它做增量】
         *
         * 早先这里直接给 _widths / _lastAvail 赋值，再在同一帧里用 _widths!。
         * 问题有两个：
         *   1. LayoutBuilder 的 builder 可能在同一帧里被调用**多次**（父级用
         *      IntrinsicHeight / 多遍布局时），第二遍会拿第一遍已经 rescale 过的
         *      宽度再 rescale 一次，越缩越窄；
         *   2. 在 build 里写 State 字段而不走 setState，属于「渲染期间修改状态」，
         *      Debug 模式下会报 setState called during build。
         *
         * 现在拆成「纯计算 + 幂等提交」：_resolveWidths 只读当前状态、算出应该
         * 用的宽度并返回，不写字段；只有当结果与已提交的宽度确实不同时，才把
         * 新值记到 _pendingWidths，等本帧布局结束后由 addPostFrameCallback 提交。
         * 同一帧内重复调用拿到的都是同一份输入，结果完全一致，不会累积漂移。 */
        final _WidthPlan plan = _resolveWidths(avail);
        if (plan.changed) {
          _pendingWidths = plan.widths;
          _pendingAvail = avail;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            if (_pendingWidths == null) {
              return;
            }
            setState(() {
              _widths = _pendingWidths;
              _lastAvail = _pendingAvail;
              _pendingWidths = null;
            });
          });
        }
        return _buildTable(context, plan.widths);
      },
    );
  }

  /// 在指定屏幕坐标弹出右键菜单，并把选择翻译成父页面的回调。
  Future<void> _openMenu(BuildContext context, Offset position) async {
    final String? choice = await _showTableMenu(context, position);
    // await 之后这个 State 可能已经被销毁（用户在菜单还开着的时候切了 Tab，
    // 或者点了右上角关闭）。此时再回调父层的 setState 就是「对已卸载的 widget
    // 调 setState」，debug 下直接抛异常。
    if (!context.mounted) {
      return;
    }
    switch (choice) {
      case 'all':
        widget.onSelectAll();
      case 'invert':
        widget.onInvertSelection();
      case 'delete':
        widget.onDeleteSelected();
      case 'deleteSucceeded':
        widget.onDeleteSucceeded();
    }
  }

  Widget _buildTable(BuildContext context, List<double> widths) {
    /* 【禁用时也要有反馈，不能静默吞掉点击】
     *
     * 运行中整表只读（产品要求：跑起来就不许改列表）。如果 onSecondaryTapDown
     * 直接给 null，右键毫无反应，用户会以为程序卡死；行点击同样为 null，
     * 勾选也没反应。所以把「被禁用」这件事显式提示出去。 */
    void reportDisabled() =>
        widget.onDisabledTap?.call('运行中不可修改列表，请先「结束」');

    return GestureDetector(
      onSecondaryTapDown: widget.enabled
          ? (TapDownDetails details) => _openMenu(context, details.globalPosition)
          : (TapDownDetails details) => reportDisabled(),
      child: Container(
        decoration: BoxDecoration(
          color: WorkColors.fieldFill,
          border: Border.all(color: WorkColors.border, width: 1),
          borderRadius: BorderRadius.circular(kRadius),
        ),
        // 圆角裁切：不裁的话表头的 headerFill 会从四个角溢出来盖住圆角。
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 表头：固定不滚动。表头本身按 1px 分隔线布局，
            // 上面再盖一层透明的「列宽抓手」，只有它响应拖动。
            SizedBox(
              height: kHeaderHeight,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: _HeaderRow(columns: widget.columns, widths: widths),
                  ),
                  Positioned.fill(
                    child: _HeaderDividerOverlay(
                      columns: widget.columns,
                      widths: widths,
                      onDragDivider: _dragDivider,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: WorkColors.border),
            // 数据区
            Expanded(
              child: widget.rows.isEmpty
                  ? _EmptyBody(hint: widget.emptyHint)
                  : _ScrollableBody(
                      columns: widget.columns,
                      rows: widget.rows,
                      selected: widget.selected,
                      onToggleSelection: widget.onToggleSelection,
                      enabled: widget.enabled,
                      onDisabledTap: widget.onDisabledTap,
                      widths: widths,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
