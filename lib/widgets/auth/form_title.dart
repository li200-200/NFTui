// ---------------------------------------------------------------------------
// 表单标题（登录 / 创建账号 / 充值）
//
// 参考图实测：标题 25 号 w600 居中，说明文字 13 号居中、行高 1.7。
//
// 说明文字可以给两行（注册页的「输入用户名,密码,卡密,」/「创建一个账户。」）。
// 用 \n 分段而不是让 Text 自动折行 —— 自动折行的断点取决于可用宽度，
// 换字号或换窗口就会变成不同的两行，参考图里的断点是刻意排的。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';

class FormTitle extends StatelessWidget {
  const FormTitle({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: kAuthTitleSize,
            fontWeight: FontWeight.w600,
            color: AuthColors.textPrimary,
            fontFamily: kFontFamily,
            fontFamilyFallback: kFontFallback,
            // 标题字距 1：25 号中文不写字距会显得字挤在一起。
            letterSpacing: 1,
          ),
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: kAuthBodySize,
              color: AuthColors.textHint,
              height: kAuthSubtitleHeight,
              fontFamily: kFontFamily,
              fontFamilyFallback: kFontFallback,
            ),
          ),
        ],
      ],
    );
  }
}
