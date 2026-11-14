// ---------------------------------------------------------------------------
// 分区标题（「登录区」「信息区」「选项区」）
//
// 参考图里 QGroupBox 的 title 是压在边框上居中的，那是 Qt 的样式约定。
// 这里刻意改成「卡片内第一行的左对齐小标题」：Flutter 的卡片是圆角描边，
// 再在边框上开口压字会把 1px 线切断，视觉上像掉了一块。文案保留原样。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';

class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: kFontBody,
          fontWeight: FontWeight.w600,
          color: WorkColors.brand,
          fontFamily: kFontFamily,
          fontFamilyFallback: kFontFallback,
          // 中文字距默认偏挤，加 0.6 让「登录区」三个字松一点。
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
