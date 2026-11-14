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
//
// 【subtitle：标题里的长说明】
// config.ui 的 groupBox_shq 把「格式：前缀-手机号-密码-支付密码」直接写进了标题，
// 于是那一行有 24 个字 —— 单行标题在 331 宽的抽屉里必然被截成省略号，信息就丢了。
// 所以拆成两行：title 是主标题（主色、w600，与其它卡片一致），subtitle 是附在
// 它后面的说明（辅助色、12 号），换行显示而不是截断。
//
// 【objectName】
// 每个卡片都对应 .ui 里一个 QGroupBox，构造时传它的 objectName，卡片会把
// `ValueKey(objectName)` 挂到最外层 Container 上。这样测试可以按 .ui 的名字
// 精确找卡片（`find.byKey(ValueKey(kGroupBoxShq))`），不必靠标题文案 ——
// 文案是会改的，objectName 是契约。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/panel_controls.dart';

class PanelGroupBox extends StatelessWidget {
  const PanelGroupBox({
    super.key,
    required this.title,
    required this.child,
    this.objectName,
    this.subtitle,
    this.padding = kGroupBoxPadding,
    this.sectionGap = kSectionGap,
  });

  /// 卡片标题。取自 .ui 的 `<property name="title">`，原样保留。
  final String title;

  /// 对应 .ui 里这个 QGroupBox 的 objectName。
  ///
  /// 传了就把 `ValueKey(objectName)` 挂到最外层 —— 用 .ui 的名字当测试锚点。
  final String? objectName;

  /// 标题里附带的说明文字（可选）。与 [title] 分行显示，不截断。
  ///
  /// 只有「上号器区」用它 —— .ui 把格式说明并进了分组标题，一行放不下。
  final String? subtitle;

  final Widget child;

  /// 卡片内边距（常规 / 紧凑两档，见 [PanelMetrics]）。
  final EdgeInsets padding;

  /// 分区标题与首个控件之间的间距。
  final double sectionGap;

  @override
  Widget build(BuildContext context) {
    final String? sub = subtitle;
    final String? name = objectName;

    return Container(
      key: name == null ? null : ValueKey<String>(name),
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
          if (sub != null) ...<Widget>[
            const SizedBox(height: kPanelSubtitleGap),
            Text(
              sub,
              style: const TextStyle(
                fontSize: kFontHint,
                color: WorkColors.textMuted,
                fontFamily: kFontFamily,
                fontFamilyFallback: kFontFallback,
                height: 1.3,
              ),
            ),
          ],
          SizedBox(height: sectionGap),
          child,
        ],
      ),
    );
  }
}
