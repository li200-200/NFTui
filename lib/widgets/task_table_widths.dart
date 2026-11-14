// ---------------------------------------------------------------------------
// 表格列宽算法（纯 Dart，无 Widget 依赖）
//
// 从 task_table.dart 里抽出来的原因：「初始宽度 / 缩放 / 拖动」三段算法混在
// StatefulWidget 的 build 与 setState 之间，既不好读也不方便单测。这里改成一组
// 纯函数，输入输出全是 List<double>，可以脱离 Flutter 直接断言。
//
// 三条不变量（改动时必须全部保住）：
//   1. **总宽恒定** —— 任何操作后各列宽之和都等于可用宽度 avail；
//   2. **每列不小于自己的 minWidth** —— 否则那一列会被压没，抓手（分隔条）
//      跟着消失，用户再也拖不回来；
//   3. **只动相邻两列** —— 拖一条分隔线时，左边加多少右边就减多少，更右边的
//      列纹丝不动（否则整表跟着平移，手感很差）。
//
// 【刻意不做持久化】需求是「打开软件使用默认的」：列宽只在本次运行内有效，
// 关掉再开回到 [TaskColumn.flex] 的比例。所以这里没有任何读写文件的代码。
// ---------------------------------------------------------------------------
import 'package:app_ui/models.dart';

/// 竖向分隔条总占宽（列数 - 1 条，每条 1px）。
double dividerTotal(List<TaskColumn> columns) =>
    (columns.length - 1).toDouble();

/// 表格内容区可用宽度 = 表格总宽 - 左右边框(2px) - 竖向分隔条。
double availableWidth(List<TaskColumn> columns, double tableWidth) =>
    (tableWidth - 2 - dividerTotal(columns)).clamp(1.0, 1e6);

/// 按默认 flex 算出初始宽度。
List<double> initialWidths(List<TaskColumn> columns, double avail) {
  final int totalFlex = columns.fold<int>(
    0,
    (int s, TaskColumn c) => s + c.flex,
  );
  if (totalFlex <= 0 || avail <= 0) {
    return <double>[for (final TaskColumn c in columns) c.minWidth];
  }
  // 按 flex 比例分完之后再精确对齐一次：`avail * flex / totalFlex` 的浮点结果
  // 累加起来可能比 avail 大一点点，那点误差在 Row 里就是真实溢出。
  return _clampToExactSum(
    columns,
    <double>[for (final TaskColumn c in columns) avail * c.flex / totalFlex],
    avail,
  );
}

/// 把当前宽度整体缩放到新的可用宽度（保持用户调好的相对比例）。
///
/// 缩放后可能某列被压到 minWidth 以下（窗口变窄时），按最小值兜底，再把多出来的
/// 宽度从最宽的那一列里扣回来，保证总宽仍然等于 [avail]。
List<double> rescaleWidths(
  List<TaskColumn> columns,
  List<double> old,
  double oldAvail,
  double avail,
) {
  if (oldAvail <= 0) {
    return initialWidths(columns, avail);
  }
  final double k = avail / oldAvail;
  final List<double> next = <double>[for (final double w in old) w * k];
  double sum = next.fold<double>(0, (double s, double w) => s + w);
  for (int i = 0; i < next.length; i++) {
    final double minW = columns[i].minWidth;
    if (next[i] < minW) {
      sum += minW - next[i];
      next[i] = minW;
    }
  }
  if (sum > avail) {
    /* 扣减：从「还有余量」的列里按比例收，直到总量对上。
     *
     * 早先这里每一轮只找**最宽**的那一列扣，扣到它的 minWidth 就 break ——
     * 那是个真 bug：最宽的列到下限时，其它列其实还有余量，但循环直接退出了，
     * 剩下的溢出量没人消化，总宽就比 avail 大出一截（实测 520 的可用宽度
     * 收出 527，表格右边多出 7px 空隙）。
     *
     * 现在每轮在**所有还有余量**的列里挑最宽的那个扣；全部到下限才退出。
     * 轮数上限按列数给足（每列最多扣一次到下限，再多留几轮给舍入）。 */
    double excess = sum - avail;
    final int maxPass = next.length * 2 + 8;
    for (int pass = 0; pass < maxPass && excess > 0.5; pass++) {
      int pick = -1;
      double pickRoom = 0;
      for (int i = 0; i < next.length; i++) {
        final double room = next[i] - columns[i].minWidth;
        if (room > pickRoom) {
          pickRoom = room;
          pick = i;
        }
      }
      // 所有列都到下限了：已经无解，留着这最后一点差额（宁可窄 1px，
      // 也不要把某列压到 minWidth 以下让抓手消失）。
      if (pick < 0 || pickRoom <= 0.5) {
        break;
      }
      final double take = excess < pickRoom ? excess : pickRoom;
      next[pick] -= take;
      excess -= take;
    }
  }
  return _clampToExactSum(columns, next, avail);
}

/// 把宽度列表的**总和**精确对齐到 [avail]，且不破坏任何列的 minWidth。
///
/// 【为什么需要这一步】
/// 上面两段逻辑（按比例缩放、从最宽列扣减）都以 0.5px 为容差提前收手，所以
/// 总和可能比 [avail] 大出零点几像素。对 `Row` 里的固定宽 `SizedBox` 来说，
/// 这零点几像素就是**真实溢出**：RenderFlex 会画黄黑警示条。实测 880x620 下
/// 溢出 0.214px —— 肉眼看不见，但测试与用户都会看到警示条。
///
/// 这里做最后一步「精确抹平」：把差额全部压到**当前最宽**的那一列上。
/// 选最宽列而不是按比例分摊，是因为它相对误差最小、且最宽列的余量必然最大，
/// 不会把某列顶到 minWidth 以下。若最宽列也吃不下，就顺次找下一宽的。
List<double> _clampToExactSum(
  List<TaskColumn> columns,
  List<double> widths,
  double avail,
) {
  final List<double> next = List<double>.of(widths);
  final double sum = next.fold<double>(0, (double s, double w) => s + w);
  double diff = sum - avail;

  // 差额小到浮点噪声级别就直接抹掉，避免无意义的多轮循环。
  if (diff.abs() < 1e-9) {
    return next;
  }

  if (diff > 0) {
    // 超了：按「余量」从大到小，逐个吃到 minWidth 为止。
    final List<int> order = <int>[
      for (int i = 0; i < next.length; i++) i,
    ]..sort((int a, int b) {
        final double ra = next[a] - columns[a].minWidth;
        final double rb = next[b] - columns[b].minWidth;
        return rb.compareTo(ra);
      });
    for (final int i in order) {
      if (diff <= 0) {
        break;
      }
      final double room = next[i] - columns[i].minWidth;
      if (room <= 0) {
        continue;
      }
      final double take = diff < room ? diff : room;
      next[i] -= take;
      diff -= take;
    }
  } else {
    // 少了：补给最宽的那一列（视觉上最不敏感）。
    int widest = 0;
    for (int i = 1; i < next.length; i++) {
      if (next[i] > next[widest]) {
        widest = i;
      }
    }
    next[widest] -= diff; // diff 为负，等价于加上 |diff|
  }
  return next;
}

/// 拖动第 [index] 条分隔条（第 index 列与第 index+1 列之间）[dx] 像素后的新宽度。
///
/// 只动相邻两列：左边加多少、右边就减多少，总宽恒定。夹在两侧 minWidth 之内，
/// 夹到 0（也就是拖不动）时返回原列表的拷贝。
List<double> dragDivider(
  List<TaskColumn> columns,
  List<double> cur,
  int index,
  double dx,
) {
  final List<double> next = List<double>.of(cur);
  if (index < 0 || index + 1 >= next.length) {
    return next;
  }
  final double leftMin = columns[index].minWidth;
  final double rightMin = columns[index + 1].minWidth;
  double clamped = dx;
  if (cur[index] + clamped < leftMin) {
    clamped = leftMin - cur[index];
  }
  if (cur[index + 1] - clamped < rightMin) {
    clamped = cur[index + 1] - rightMin;
  }
  if (clamped == 0) {
    return next;
  }
  next[index] = next[index] + clamped;
  next[index + 1] = next[index + 1] - clamped;
  return next;
}

/// 宽度是否与上一份实质相同（用于避免多余的 setState）。
bool widthsClose(List<double> a, List<double> b, {double eps = 0.5}) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > eps) {
      return false;
    }
  }
  return true;
}
