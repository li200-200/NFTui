// ---------------------------------------------------------------------------
// 工作台顶部标题条：拖动区 + 最小化 / 关闭
//
// 高度 38，底色面板灰、下边框 1px。原生层已隐藏系统标题栏
// （Windows runner 用 WS_POPUP + window_manager 的 TitleBarStyle.hidden），
// 所以这一条既是标题也是唯一的窗口控制入口。
//
// 为什么右侧只有「最小化 / 关闭」两个方形小按钮：38px 高的标题条放圆形按钮
// 不协调，而且这一层不需要「返回登录页」之类的业务入口。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:app_ui/theme.dart';

class WorkTitleBar extends StatelessWidget {
  const WorkTitleBar({super.key, this.title = kWindowTitle});

  /// 标题文案。默认取 .ui 的 windowTitle（「阿萨德」），原样保留。
  final String title;

  @override
  Widget build(BuildContext context) {
    /* 原生标题栏被隐藏了，拖动窗口这件事必须自己补上。
     *
     * 只挂 onPanStart：按下不动就抬起时，PanGestureRecognizer 不会赢下手势竞技场，
     * 点击照常落到右侧的最小化 / 关闭按钮上；一旦横向或纵向拖动超过 slop，
     * 就交给系统拖动窗口 —— 与 Windows 原生标题栏的手感一致。 */
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      child: _buildBar(),
    );
  }

  Widget _buildBar() {
    return Container(
      height: kTitleBarHeight,
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: const BoxDecoration(
        color: WorkColors.panel,
        border: Border(bottom: BorderSide(color: WorkColors.border, width: 1)),
      ),
      child: Row(
        children: <Widget>[
          // 主色圆点：与验证页的品牌标识同一套语言。
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: WorkColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          /* 【标题必须用 Flexible(fit: loose) 且不能跟 Spacer 并列】
           *
           * Flexible 默认 fit: FlexFit.loose，它仍然参与 flex 分配：标题（flex 1）
           * 和 Spacer（flex 1）会各分到一半剩余空间，于是标题右边界停在窗口
           * 中间偏左的位置，右侧按钮被推到 ~63% 处而不是贴住右边 —— 这正是
           * 「最小化 / 关闭不在最右边」的原因。
           *
           * 两个改法任选：给标题 fit: tight（它会吃满分到的空间，把 Spacer
           * 挤成 0），或者干脆不要 Spacer、让标题自己去推。这里选后者 ——
           * 标题用 Expanded 吃掉全部剩余宽度，右侧按钮自然被推到最右端；
           * 文字本身靠左对齐，长标题仍会按 ellipsis 截断，不会把按钮挤出去。 */
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: kFontBody,
                  fontWeight: FontWeight.w600,
                  color: WorkColors.textPrimary,
                  fontFamily: kFontFamily,
                  fontFamilyFallback: kFontFallback,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
          const _CaptionBar(),
        ],
      ),
    );
  }
}

/// 右上角的最小化 / 关闭。
class _CaptionBar extends StatelessWidget {
  const _CaptionBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _CaptionButton(
          tooltip: '最小化',
          icon: Icons.remove,
          onTap: windowManager.minimize,
        ),
        const SizedBox(width: 2),
        _CaptionButton(
          tooltip: '关闭',
          icon: Icons.close,
          danger: true,
          // 用 close() 而不是 destroy()：destroy() 只发 PostQuitMessage，
          // 窗口要等引擎析构完才消失，点下去会僵一会儿。
          onTap: windowManager.close,
        ),
      ],
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final Color base = widget.danger ? WorkColors.danger : WorkColors.textHint;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: kHoverDuration,
            curve: Curves.easeOut,
            width: 30,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? base.withValues(alpha: 0.14) : Colors.transparent,
              borderRadius: BorderRadius.circular(kTitleButtonRadius),
            ),
            child: Icon(widget.icon, size: 15, color: base),
          ),
        ),
      ),
    );
  }
}
