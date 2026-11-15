// ---------------------------------------------------------------------------
// 方框勾选（记住密码 / 自动登录）
//
// 实测 18x18、圆角 3、勾 13px。
//
// 注意：页脚「✓我同意」用的也是 Icons.check，尺寸 12 —— 测试里靠这两个尺寸
// 区分「勾选框里的勾」与「页脚的勾」，改动任一处都要同步检查相关断言。
//
// 【与工作台 SwitchRow 的关系】
// 工作台用开关（32x16 轨道），验证页用方框 —— 这是两套视觉语言的一部分，
// 不要为了「统一」把其中一个改掉。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';

class CheckPill extends StatelessWidget {
  const CheckPill({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.size = 18,
    this.fontSize = 13,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: value ? AuthColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: value ? AuthColors.primary : AuthColors.textMuted,
                  width: 1.2,
                ),
              ),
              child: value
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                color: AuthColors.textHint,
                fontFamily: kFontFamily,
                fontFamilyFallback: kFontFallback,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
