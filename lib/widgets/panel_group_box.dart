// ---------------------------------------------------------------------------
// 面板卡片（对应 .ui 里的 QGroupBox）
//
// Qt 的 QGroupBox 把 title 压在边框上居中显示。这里改成「圆角卡片 + 卡片内
// 第一行的左对齐小标题」：Flutter 的卡片是 1px 描边 + 4px 圆角，若在边框上
// 开口压字，那 1px 线会被切断一截，看着像掉了一块漆。文案原样保留。
//
// 【为什么用 Container 而不是 Card】
// Card 自带 1dp 的 elevation 与 Material 的 surfaceTint，在这套扁平配色里会
// 出现一层灰雾。这里只要「底色 + 1px 边框 + 圆角」，Container 足够且可控。
//
// 【padding 为什么从外面传】
// 窗口压到最小尺寸时左栏要靠收紧内边距腾出高度（见 theme.dart 的 PanelMetrics
// 说明）。卡片自己不判断窗口大小，只接受调用方给的一档，逻辑留在页面里。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/panel_controls.dart';

class PanelGroupBox extends StatelessWidget {
  const PanelGroupBox({
    super.key,
    required this.title,
    required this.child,
    this.padding = kGroupBoxPadding,
    this.sectionGap = kSectionGap,
  });

  /// 卡片标题。取自 .ui 的 `<property name="title">`，原样保留。
  final String title;

  final Widget child;

  /// 卡片内边距（常规 / 紧凑两档，见 [PanelMetrics]）。
  final EdgeInsets padding;

  /// 分区标题与首个控件之间的间距。
  final double sectionGap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: WorkColors.panel,
        border: Border.all(color: WorkColors.border, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SectionLabel(text: title),
          SizedBox(height: sectionGap),
          child,
        ],
      ),
    );
  }
}
