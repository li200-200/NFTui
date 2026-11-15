// ---------------------------------------------------------------------------
// 文字链接
//
// 页脚（联系领航 / 软件使用协议）与表单里的「注册账号」「充值」都用它。
//
// 悬停变主色深一档并加下划线：验证页里链接很多，纯靠颜色区分不够 ——
// 页脚那几个字本身是灰的，不加深就看不出能点。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';

class LinkText extends StatefulWidget {
  const LinkText({
    super.key,
    required this.text,
    required this.onTap,
    this.fontSize = 12.5,
    this.color,
    this.bold = false,
  });

  final String text;
  final VoidCallback onTap;
  final double fontSize;

  /// 默认用品牌绿。页脚的「联系领航」用它，正文里的强调链接也用它。
  final Color? color;

  /// 「注册账号」这类行动号召用 w600。
  final bool bold;

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final Color base = widget.color ?? AuthColors.brand;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Text(
          widget.text,
          style: TextStyle(
            fontSize: widget.fontSize,
            color: _hover ? AuthColors.primaryDark : base,
            fontWeight: widget.bold ? FontWeight.w600 : FontWeight.w400,
            fontFamily: kFontFamily,
            fontFamilyFallback: kFontFallback,
            // 下划线只在悬停时出现：常驻下划线在 12.5 号字上很吵。
            decoration: _hover ? TextDecoration.underline : TextDecoration.none,
            decorationColor: AuthColors.primaryDark,
          ),
        ),
      ),
    );
  }
}
