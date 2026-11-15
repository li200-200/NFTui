// ---------------------------------------------------------------------------
// 小号表格（对应 config.ui 里「小号区」的 QTableWidget）
//
// 三列固定：no / phone / token。与右侧主表格的差别是刻意的 ——
//   · 主表格 9 列、可拖动列宽、三套列定义、按状态着色；
//   · 这里是设置页里的「小号清单」，3 列固定宽度、只有最基本的交互：
//     点行选中（可多选）、右键出菜单。
//
// 【交互只有两项，与主表格刻意不同】
//   · 点一行 → 切换选中态（左侧主色竖条 + 浅底，与主表格同一套视觉）；
//   · 右键 → 菜单「全选 / 删除选中小号」。**没有**「反选 / 删除成功」——
//     那两项是任务状态机的概念（按 status 筛行），小号没有状态。
//
// 【为什么不复用 TaskTable】
// TaskTable 是为「运行中的任务」设计的：9 列、可拖宽、右键删除、按状态着色。
// 套到这张 3 列小表上，要么关掉一半功能（传一堆 null 回调），要么让它
// 变得比表本身还复杂。这里重写一个精简表更干净。
//
// 【列宽为什么是 34 / 1fr / 1fr】
// 早先三列等分，no 列拿到 104px 而它只放「1」…「10」—— 空出一大片，反倒把
// phone（11 位手机号约 77px）与 token 挤到出省略号。现在 no 固定 34（放得下
// 两位数 + 左右内边距），剩余宽度两列平分，手机号与 token 都能完整显示。
//
// 【为什么要限高 + 内部滚动】
// 数据条数不固定，若按内容撑开，10 条会让表格高到 266px，把下面两个分组挤出
// 抽屉。所以保留「限高的框」这个原始意图，数据超出就在框内滚动。
//
// 【高度随行数自适应：空表 2 行、有数据最多 5 行】
// 早先高度固定 168（表头 + 6 行）。固定高度有两个问题：
//   · 空表时框里一大片空白，只剩「暂无小号」几个字飘在中间，看不出「本该有几行」；
//   · 只有 1~2 条数据时框仍然撑到 6 行高，白白占掉抽屉高度。
// 现在按实际行数算：空表显示 [kSettingTableMinRows] 行（2 行，明确表达「这里
// 该有数据」而不是塌成一条表头），有数据时按条数算但不超过
// [kSettingTableMaxRows] 行（5 行），超出部分框内滚动。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/table_menu.dart';

/// 小号表的一行。
class SubAccount {
  const SubAccount({
    required this.no,
    required this.phone,
    required this.token,
  });

  final String no;
  final String phone;
  final String token;
}

/// 小号表的三列标题。取自 config.ui 的 `<column><property name="text">`。
const List<String> kSubAccountColumns = <String>['no', 'phone', 'token'];

/// 十条模拟数据。
///
/// 手机号用 138/139/137… 这些常见号段递增，token 用 `tk_` + 4 位十六进制，
/// 与实际抓包里看到的形态一致。no 从 1 开始 —— 与 .ui 表格的行号语义一致。
const List<SubAccount> kDemoSubAccounts = <SubAccount>[
  SubAccount(no: '1', phone: '13800138000', token: 'tk_9f2a'),
  SubAccount(no: '2', phone: '13900139001', token: 'tk_4b7c'),
  SubAccount(no: '3', phone: '13700137002', token: 'tk_1c3d'),
  SubAccount(no: '4', phone: '13600136003', token: 'tk_7d2e'),
  SubAccount(no: '5', phone: '13500135004', token: 'tk_8a1f'),
  SubAccount(no: '6', phone: '13400134005', token: 'tk_2e9b'),
  SubAccount(no: '7', phone: '13300133006', token: 'tk_5f4a'),
  SubAccount(no: '8', phone: '13200132007', token: 'tk_6b8c'),
  SubAccount(no: '9', phone: '13100131008', token: 'tk_3a7d'),
  SubAccount(no: '10', phone: '13000130009', token: 'tk_0c5e'),
];

/// 小号表：表头固定 + 数据区可滚动，支持点行选中与右键菜单。
///
/// 【为什么是 StatefulWidget】
/// 两个原因：
///   · `Scrollbar.thumbVisibility: true` 要求显式提供一个 ScrollController ——
///     没有的话它会去要 PrimaryScrollController，而抽屉里没有，运行时会抛
///     「A ScrollController is required when Scrollbar.thumbVisibility is true」。
///     控制器必须在 State 里持有：放进 build 里现造，每帧换新实例，滚动位置会被
///     重置（这个坑主表格已经踩过一次，见 task_table_body.dart 的说明）。
///   · 选中态要跨重建保留（切 Tab、刷新数据都不该清空用户的选择）。
///
/// 【objectName】
/// 对应 config.ui 的 `tableWidget_xh`，构造时由调用方把那个名字传进来当 Key
/// （`key: const ValueKey(kTableWidgetXh)`），测试据此定位，不依赖列名文案。
class SubAccountTable extends StatefulWidget {
  const SubAccountTable({
    super.key,
    required this.rows,
    this.columns = kSubAccountColumns,
    this.selected = const <int>{},
    this.onToggleSelection,
    this.onSelectAll,
    this.onDeleteSelected,
  });

  final List<SubAccount> rows;
  final List<String> columns;

  /// 被选中行的下标集合。
  ///
  /// 【由父页面持有还是组件自己持有】
  /// 这里做成「可传可不传」：传了就用父页面的（便于父页面执行删除、也便于
  /// 测试直接断言），不传就由组件内部维护。实际使用中父页面总是会传 ——
  /// 「删除选中小号」需要知道删哪些，那个动作必须发生在数据持有者那一层。
  final Set<int> selected;

  /// 点某一行：切换它的选中态。为 null 时组件内部自己切。
  final ValueChanged<int>? onToggleSelection;

  /// 右键菜单「全选」。
  final VoidCallback? onSelectAll;

  /// 右键菜单「删除选中小号」。
  final VoidCallback? onDeleteSelected;

  @override
  State<SubAccountTable> createState() => _SubAccountTableState();
}

class _SubAccountTableState extends State<SubAccountTable> {
  final ScrollController _controller = ScrollController();

  /// 父页面没接管选中态时用的内部集合。
  final Set<int> _ownSelected = <int>{};

  /// 当前生效的选中集合。
  ///
  /// 【判据是「父页面有没有接管」，不是「集合空不空」】
  /// 早先想用 `widget.selected.isNotEmpty` 来判断，那是错的：父页面接管了、
  /// 但用户还没选任何行时，那个集合就是空的 —— 会被误判成「没接管」，
  /// 于是点第一行时组件去改内部集合，父页面收不到变化，界面毫无反应。
  /// 所以看回调在不在：`onToggleSelection != null` 就是父页面接管了。
  Set<int> get _selected =>
      widget.onToggleSelection != null ? widget.selected : _ownSelected;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 当前要显示几行（决定外框高度）。
  ///
  /// 空表按 [kSettingTableMinRows] 算（2 行），有数据按实际条数算但封顶
  /// [kSettingTableMaxRows]（5 行）。用条数而不是「有没有滚动」来判断：
  /// 后者要等布局完成才知道，会出现「先矮后高」的一帧跳变。
  int get _visibleRows {
    final int n = widget.rows.length;
    if (n == 0) {
      return kSettingTableMinRows;
    }
    return n < kSettingTableMaxRows ? n : kSettingTableMaxRows;
  }

  /// 点一行：切换它的选中态。
  void _toggle(int index) {
    final ValueChanged<int>? callback = widget.onToggleSelection;
    if (callback != null) {
      callback(index);
      return;
    }
    // 没人接管：自己切，然后重建。
    setState(() {
      if (!_ownSelected.remove(index)) {
        _ownSelected.add(index);
      }
    });
  }

  /// 右键：弹出菜单并执行选中的动作。
  ///
  /// 【为什么位置用 event.position 而不是 localPosition】
  /// showMenu 要的是全局坐标（它内部按 Overlay 的坐标系摆放）。传局部坐标会
  /// 让菜单出现在屏幕左上角附近，而不是鼠标那一点。
  Future<void> _showMenuAt(Offset globalPosition) async {
    final String? choice = await showTableMenu(
      context,
      globalPosition,
      const <TableMenuItem>[
        TableMenuItem(value: 'all', label: '全选'),
        // 只有「删除选中小号」—— 小号没有状态机，不需要「反选 / 删除成功」。
        TableMenuItem(value: 'delete', label: '删除选中小号', danger: true),
      ],
    );
    if (!mounted || choice == null) return;

    switch (choice) {
      case 'all':
        final VoidCallback? selectAll = widget.onSelectAll;
        if (selectAll != null) {
          selectAll();
          return;
        }
        setState(() {
          _ownSelected
            ..clear()
            ..addAll(<int>[for (int i = 0; i < widget.rows.length; i++) i]);
        });
      case 'delete':
        final VoidCallback? deleteSelected = widget.onDeleteSelected;
        if (deleteSelected != null) {
          deleteSelected();
          return;
        }
        // 没人接管：至少把内部选中清掉，让界面有反馈。
        setState(_ownSelected.clear);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<SubAccount> rows = widget.rows;
    return Container(
      // 表头 + N 行 + 上下边框。N 由数据条数决定（2~5）。
      height:
          kSettingTableHeaderHeight +
          kSettingTableRowHeight * _visibleRows +
          kSettingTableBorderWidth * 2,
      decoration: BoxDecoration(
        color: WorkColors.fieldFill,
        border: Border.all(
          color: WorkColors.border,
          width: kSettingTableBorderWidth,
        ),
        borderRadius: BorderRadius.circular(kRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 表头：底色比数据区深一档，与主表格的 TaskTableHeader 同一个视觉。
          Container(
            height: kSettingTableHeaderHeight,
            decoration: const BoxDecoration(
              color: WorkColors.panel,
              border: Border(
                bottom: BorderSide(color: WorkColors.border, width: 1),
              ),
            ),
            child: Row(
              children: <Widget>[
                for (int i = 0; i < widget.columns.length; i++)
                  _cellSlot(i, _Cell(text: widget.columns[i], header: true)),
              ],
            ),
          ),
          Expanded(
            child: rows.isEmpty
                // 空表：留 2 行的空白 + 居中提示。不是塌成一条表头 ——
                // 那样看起来像加载失败，而不是「确实没有数据」。
                ? const Center(
                    child: Text(
                      '暂无小号',
                      style: TextStyle(
                        fontSize: kFontHint,
                        color: WorkColors.textHint,
                        fontFamily: kFontFamily,
                        fontFamilyFallback: kFontFallback,
                      ),
                    ),
                  )
                : Scrollbar(
                    controller: _controller,
                    // 只有真的超出 5 行才需要滚动条；不足 5 行时不占位。
                    thumbVisibility: rows.length > kSettingTableMaxRows,
                    thickness: kScrollThickness,
                    radius: const Radius.circular(kScrollRadius),
                    child: ListView.builder(
                      controller: _controller,
                      padding: EdgeInsets.zero,
                      itemCount: rows.length,
                      itemExtent: kSettingTableRowHeight,
                      itemBuilder: (BuildContext context, int i) {
                        return _SubAccountRow(
                          row: rows[i],
                          index: i,
                          selected: _selected.contains(i),
                          last: i == rows.length - 1,
                          onTap: () => _toggle(i),
                          onSecondaryTap: _showMenuAt,
                          cellSlot: _cellSlot,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 第 [index] 列的宽度分配：no 固定 [kSettingTableNoWidth]，其余等分。
  ///
  /// 写成方法而不是在 Row 里写 if：表头与数据行必须用**同一套**宽度规则，
  /// 否则表头与列内容会错位（这类错位在截图里一眼就能看出来）。
  Widget _cellSlot(int index, Widget child) {
    if (index == 0) {
      return SizedBox(width: kSettingTableNoWidth, child: child);
    }
    return Expanded(child: child);
  }
}

/// 小号表的一行数据：可点选中、可右键出菜单。
///
/// 【选中视觉与主表格一致】
/// 浅主色底 + 左侧 3px 主色竖条。竖条用 foregroundDecoration 画而不是塞一个
/// 子节点 —— 子节点会挤占行内宽度，三列整体右移 3px，与表头错位。
class _SubAccountRow extends StatefulWidget {
  const _SubAccountRow({
    required this.row,
    required this.index,
    required this.selected,
    required this.last,
    required this.onTap,
    required this.onSecondaryTap,
    required this.cellSlot,
  });

  final SubAccount row;
  final int index;
  final bool selected;

  /// 是否最后一行。最后一行不画下边框（外框已经有一条）。
  final bool last;

  final VoidCallback onTap;
  final ValueChanged<Offset> onSecondaryTap;

  /// 列宽分配函数由父 State 提供，保证表头与数据行用同一套规则。
  final Widget Function(int index, Widget child) cellSlot;

  @override
  State<_SubAccountRow> createState() => _SubAccountRowState();
}

class _SubAccountRowState extends State<_SubAccountRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool selected = widget.selected;
    final Color base = selected
        ? WorkColors.primarySoft
        : (widget.index.isOdd ? WorkColors.rowAlt : WorkColors.fieldFill);
    // 悬停再加深一档：选中行更明显，未选中行给一点「可点」的反馈。
    final Color background = _hover
        ? (selected
              ? WorkColors.primary.withValues(alpha: 0.22)
              : WorkColors.primary.withValues(alpha: 0.07))
        : base;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        // 右键菜单：用 event.position（全局坐标），见 _showMenuAt 的说明。
        onSecondaryTapUp: (TapUpDetails d) => widget.onSecondaryTap(d.globalPosition),
        child: AnimatedContainer(
          duration: kHoverDuration,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: background,
            border: widget.last
                ? null
                : const Border(
                    bottom: BorderSide(color: WorkColors.border, width: 1),
                  ),
          ),
          foregroundDecoration: selected
              ? const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: WorkColors.primary, width: 3),
                  ),
                )
              : null,
          child: Row(
            children: <Widget>[
              widget.cellSlot(0, _Cell(text: widget.row.no)),
              widget.cellSlot(1, _Cell(text: widget.row.phone)),
              widget.cellSlot(2, _Cell(text: widget.row.token)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.text, this.header = false});

  final String text;
  final bool header;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: header ? kFontHint : kFontBody,
            fontWeight: header ? FontWeight.w600 : FontWeight.w400,
            color: header ? WorkColors.textMuted : WorkColors.textPrimary,
            fontFamily: kFontFamily,
            fontFamilyFallback: kFontFallback,
          ),
        ),
      ),
    );
  }
}
