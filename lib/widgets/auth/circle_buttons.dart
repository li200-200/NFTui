// ---------------------------------------------------------------------------
// 右上角圆形按钮：返回 / 关闭
//
// 两个按钮尺寸统一 26x26，这样并排放在同一排时中心线自然对齐。
// 顺序与摆放由 window_chrome.dart 的 WindowControls 统一负责。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';

/// 返回按钮（回旋箭头），绿色
class CircleBackButton extends StatefulWidget {
  const CircleBackButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<CircleBackButton> createState() => _CircleBackButtonState();
}

class _CircleBackButtonState extends State<CircleBackButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '返回',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hover
                  ? AuthColors.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
            ),
            child: Icon(
              Icons.refresh,
              size: 19,
              color: _hover ? AuthColors.primaryDark : AuthColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 关闭按钮。常态是一枚红色圆点（和参考图一致），
/// 悬停时浮现 ✕，避免「这个红点能点吗」的困惑。
class CircleCloseButton extends StatefulWidget {
  const CircleCloseButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<CircleCloseButton> createState() => _CircleCloseButtonState();
}

class _CircleCloseButtonState extends State<CircleCloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '关闭',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hover
                  ? AuthColors.danger.withValues(alpha: 0.16)
                  : Colors.transparent,
            ),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 15,
                height: 15,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AuthColors.danger,
                ),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 140),
                  opacity: _hover ? 1.0 : 0.0,
                  child: const Icon(Icons.close, size: 10, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
