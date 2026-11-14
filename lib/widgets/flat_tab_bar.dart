// ---------------------------------------------------------------------------
// 扁平标签条（对应 .ui 的 QTabWidget：运行 / 订单信息 / 完成）
//
// 【为什么不用 Material 的 TabBar】
// 它自带三样这套 UI 不要的东西：滑动指示器（AnimatedIndicator）、点击水波纹、
// 以及默认的 48 高与 Material 字号。压制它们要写一堆覆盖，还不如自建 ——
// 这个标签条的全部逻辑就是「一行等高文本 + 底部 2px 下划线」。
//
// 切换动画刻意不做：桌面端工具软件的标签切换是瞬时的，滑动动画反而让人等。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';

class FlatTabBar extends StatelessWidget {
  const FlatTabBar({
    super.key,
    required this.tabs,
    required this.index,
    required this.onChanged,
  });

  /// 标签文案。取自 .ui 里三个 QWidget 的 title，顺序不变。
  final List<String> tabs;

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kTabBarHeight,
      decoration: const BoxDecoration(
        color: WorkColors.fieldFill,
        // 整条标签的下边框：它与下方表格的上边框不是同一条 —— 表格自己也有
        // 1px 外框，两者之间留 8px 间距，视觉上是「标签条 / 表格」两个块。
        border: Border(bottom: BorderSide(color: WorkColors.border, width: 1)),
      ),
      /* 【为什么标签条要能横向滚动】
       * 三个标签各约 70-90px（12.5 号中文 + 左右各 18 内边距），合计约 230px。
       * 窗口宽度正常时绰绰有余，但右栏被压到 230px 以下时 Row 就会溢出
       * （实测 400 宽窗口下溢出 66px，屏幕上出现黄黑警示条）。
       *
       * 用横向滚动而不是让标签收缩成省略号：标签是导航，缩成「运…」比滚一下
       * 更难用。窗口最小宽 880 时永远滚不到，所以不影响现有观感。 */
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (int i = 0; i < tabs.length; i++)
              _TabItem(
                label: tabs[i],
                selected: i == index,
                onTap: () => onChanged(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabItem extends StatefulWidget {
  const _TabItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool selected = widget.selected;
    // 未选中：textHint；悬停：提亮到 textPrimary；选中：textPrimary + 加粗。
    final Color color = selected
        ? WorkColors.textPrimary
        : (_hover ? WorkColors.textPrimary : WorkColors.textHint);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: kHoverDuration,
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: kTabPadding),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // 悬停垫主色 6%：选中项已经有下划线了，再垫底色会显得「选中了两次」。
            color: (_hover && !selected)
                ? WorkColors.primary.withValues(alpha: 0.06)
                : Colors.transparent,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: kFontBody,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                  fontFamily: kFontFamily,
                  fontFamilyFallback: kFontFallback,
                ),
              ),
              const SizedBox(height: 5),
              // 下划线：选中 2px 主色，未选中同高透明 —— 用固定高度的占位而不是
              // 条件插入，否则选中 / 未选中的文字基线会差 2px，切换时整行抖一下。
              AnimatedContainer(
                duration: kStateDuration,
                curve: Curves.easeOut,
                height: kTabUnderline,
                width: 22,
                decoration: BoxDecoration(
                  color: selected ? WorkColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
