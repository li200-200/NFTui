// ---------------------------------------------------------------------------
// 列宽算法单测
//
// 这些断言守的是 task_table_widths.dart 里的三条不变量：
//   1. 总宽恒定；
//   2. 每列不小于 minWidth；
//   3. 拖动只动相邻两列。
// 一旦哪条被破坏，界面上表现为「表头与数据行错位」「某列拖没了拖不回来」，
// 这类问题靠肉眼很难在每次改动后重验，所以钉在这里。
// ---------------------------------------------------------------------------
import 'package:flutter_test/flutter_test.dart';

import 'package:app_ui/models.dart';
import 'package:app_ui/widgets/task_table_widths.dart';

double sum(List<double> v) => v.fold<double>(0, (double s, double w) => s + w);

void main() {
  const double avail = 700;

  test('初始宽度之和等于可用宽度', () {
    for (final List<TaskColumn> columns in <List<TaskColumn>>[
      kRunColumns,
      kOrderColumns,
      kDoneColumns,
    ]) {
      final List<double> w = initialWidths(columns, avail);
      expect(w.length, columns.length);
      expect(sum(w), closeTo(avail, 0.001));
    }
  });

  test('窗口变窄后重新缩放，总宽仍等于新宽度且不低于 minWidth', () {
    for (final List<TaskColumn> columns in <List<TaskColumn>>[
      kRunColumns,
      kOrderColumns,
      kDoneColumns,
    ]) {
      final List<double> w0 = initialWidths(columns, 900);
      final List<double> w1 = rescaleWidths(columns, w0, 900, 520);
      expect(sum(w1), closeTo(520, 0.001));
      for (int i = 0; i < columns.length; i++) {
        expect(w1[i], greaterThanOrEqualTo(columns[i].minWidth - 0.001));
      }
    }
  });

  test('拖动只改被拖列与其右邻列', () {
    final List<double> w0 = initialWidths(kRunColumns, avail);
    // 位移取 15：右邻列（token，minWidth 60）在 700 宽下只有约 81px，
    // 拖 24 就会先撞上它的 minWidth 被夹住，测不到「按原样搬运」这条性质。
    final List<double> w1 = dragDivider(kRunColumns, w0, 2, 15);
    expect(sum(w1), closeTo(sum(w0), 0.001));
    expect(w1[2], closeTo(w0[2] + 15, 0.001));
    expect(w1[3], closeTo(w0[3] - 15, 0.001));
    for (int i = 0; i < w0.length; i++) {
      if (i != 2 && i != 3) {
        expect(w1[i], w0[i]);
      }
    }
  });

  test('拖到 minWidth 就夹住，不会把列拖没', () {
    final List<double> w0 = initialWidths(kRunColumns, avail);
    // 往左猛拖 1000px：被拖列应当停在 minWidth，右邻列吃掉全部宽度。
    final List<double> w1 = dragDivider(kRunColumns, w0, 0, -1000);
    expect(w1[0], closeTo(kRunColumns[0].minWidth, 0.001));
    expect(sum(w1), closeTo(sum(w0), 0.001));

    // 往右猛拖 1000px：右邻列停在 minWidth。
    final List<double> w2 = dragDivider(kRunColumns, w0, 0, 1000);
    expect(w2[1], closeTo(kRunColumns[1].minWidth, 0.001));
    expect(sum(w2), closeTo(sum(w0), 0.001));
  });

  test('可用宽度扣掉了边框与竖向分隔条', () {
    // 9 列 → 8 条 1px 分隔条 + 左右各 1px 边框。
    expect(availableWidth(kRunColumns, 831), closeTo(831 - 2 - 8, 0.001));
    // 8 列 → 7 条。
    expect(availableWidth(kOrderColumns, 831), closeTo(831 - 2 - 7, 0.001));
  });

  test('widthsClose 在 0.5px 以内认为是同一份宽度', () {
    expect(widthsClose(<double>[1, 2, 3], <double>[1, 2, 3.4]), isTrue);
    expect(widthsClose(<double>[1, 2, 3], <double>[1, 2, 4]), isFalse);
    expect(widthsClose(<double>[1, 2], <double>[1, 2, 3]), isFalse);
  });

  test('三张表的表头文案与 .ui 完全一致且顺序不变', () {
    expect(
      kRunColumns.map((TaskColumn c) => c.title).toList(),
      <String>[
        'no',
        'phone',
        'paypwd',
        'token',
        '藏品信息',
        '数量',
        '价格',
        '状态',
        '任务详情',
      ],
    );
    expect(
      kOrderColumns.map((TaskColumn c) => c.title).toList(),
      <String>[
        'no',
        'phone',
        'paypwd',
        'token',
        '藏品信息',
        'Oid',
        '状态',
        '任务详情',
      ],
    );
    expect(
      kDoneColumns.map((TaskColumn c) => c.title).toList(),
      <String>[
        'no',
        'phone',
        'paypwd',
        'token',
        '藏品信息',
        'Oid',
        '支付链接',
        '状态',
        '任务详情',
      ],
    );
  });
}
