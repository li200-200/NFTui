// ---------------------------------------------------------------------------
// 小号表格（对应 config.ui 里「小号区」的 QTableWidget）
//
// 三列固定：no / phone / token。与右侧主表格的差别是刻意的 ——
//   · 主表格支持拖动列宽、右键菜单、多选、三套列定义；
//   · 这里是设置页里的「附加信息表」，只读、固定列宽、没有交互。
//
// 【为什么不复用 TaskTable】
// TaskTable 是为「运行中的任务」设计的：9 列、可拖宽、右键删除、按状态着色。
// 套到这张 3 列只读小表上，要么关掉一半功能（传一堆 null 回调），要么让它
// 变得比表本身还复杂。这里重写一个只读表更干净。
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

/// 只读小号表：表头固定 + 数据区可滚动。
///
/// 【为什么是 StatefulWidget】
/// `Scrollbar.thumbVisibility: true` 要求显式提供一个 ScrollController ——
/// 没有的话它会去要 PrimaryScrollController，而抽屉里没有，运行时会抛
/// 「A ScrollController is required when Scrollbar.thumbVisibility is true」。
/// 控制器必须在 State 里持有：放进 build 里现造，每帧换新实例，滚动位置会被
/// 重置（这个坑主表格已经踩过一次，见 task_table_body.dart 的说明）。
///
/// 【objectName】
/// 对应 config.ui 的 `tableWidget_xh`，构造时由调用方把那个名字传进来当 Key
/// （`key: const ValueKey(kTableWidgetXh)`），测试据此定位，不依赖列名文案。
class SubAccountTable extends StatefulWidget {
  const SubAccountTable({
    super.key,
    required this.rows,
    this.columns = kSubAccountColumns,
  });

  final List<SubAccount> rows;
  final List<String> columns;

  @override
  State<SubAccountTable> createState() => _SubAccountTableState();
}

class _SubAccountTableState extends State<SubAccountTable> {
  final ScrollController _controller = ScrollController();

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
                        return Container(
                          decoration: BoxDecoration(
                            color: i.isOdd
                                ? WorkColors.rowAlt
                                : WorkColors.fieldFill,
                            border: const Border(
                              bottom: BorderSide(
                                color: WorkColors.border,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: <Widget>[
                              _cellSlot(0, _Cell(text: rows[i].no)),
                              _cellSlot(1, _Cell(text: rows[i].phone)),
                              _cellSlot(2, _Cell(text: rows[i].token)),
                            ],
                          ),
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
