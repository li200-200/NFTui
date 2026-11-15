// ---------------------------------------------------------------------------
// 认证页面的通用骨架
//
// 布局比例按参考图实测：
//   左插画 : 右表单 = 295 : 441 ≈ 40% : 60%
//   表单列宽 280（实测输入框 x 385-664），水平居中于右栏
//   页脚固定在右下角
//
// 右上角那排窗口按钮（返回 / 关闭）统一由本骨架摆放，
// 三个页面不必各自再 Positioned 一次 —— 位置对不齐是很难看出来的。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/pages/agreement_page.dart';
import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/auth_controls.dart';
import 'package:app_ui/widgets/illustration_panel.dart';
import 'package:app_ui/widgets/window_chrome.dart';

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.children,
    this.formWidth = kAuthFormWidth,
    this.showFooter = true,
    this.onBack,
    this.onClose,
  });

  /// 表单区内容
  final List<Widget> children;

  /// 表单列宽度，实测 280
  final double formWidth;

  final bool showFooter;

  /// 非空时才显示返回按钮。登录页是首页，没有上一级，所以不传。
  final VoidCallback? onBack;

  /// 关闭按钮的回调，为空时由 WindowControls 走默认的销毁窗口。
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 左插画 40%
            const Expanded(
              flex: kAuthIllustrationFlex,
              child: IllustrationPanel(),
            ),
            // 右表单 60%
            Expanded(
              flex: kAuthFormFlex,
              child: Stack(
                children: <Widget>[
                  if (showFooter) const _PageFooter(),
                  _buildForm(),
                ],
              ),
            ),
          ],
        ),

        // 右上角：返回 + 关闭，同一顶点左右平行
        Positioned(
          top: 6,
          right: 6,
          child: WindowControls(onBack: onBack, onClose: onClose),
        ),
      ],
    );
  }

  Widget _buildForm() {
    // 窗口 800x550，纵向余量不宽裕，所以这里只留最小必要的留白：
    //   · 顶部 16，保证内容不会贴到右上角那排窗口按钮上
    //   · 底部 42，给右下的「联系领航 / ✓我同意 / 软件使用协议」让位
    // 表单整体垂直居中；真的放不下时才滚动。
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 42),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: formWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// 右下角页脚：联系领航 / 我同意 / 软件使用协议
class _PageFooter extends StatelessWidget {
  const _PageFooter();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 20,
      bottom: 8,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const LinkText(
            text: '联系领航',
            fontSize: 12.5,
            onTap: _noop,
          ),
          const SizedBox(width: 14),
          const Icon(
            Icons.check,
            size: 12,
            color: AuthColors.textMuted,
          ),
          const SizedBox(width: 3),
          const Text(
            '我同意',
            style: TextStyle(
              fontSize: 12.5,
              color: AuthColors.textMuted,
              fontFamily: kFontFamily,
              fontFamilyFallback: kFontFallback,
            ),
          ),
          const SizedBox(width: 5),
          LinkText(
            text: '软件使用协议',
            fontSize: 12.5,
            // 点这里弹出网络协议页面，正文在 pages/agreement_page.dart
            onTap: () => openAgreementPage(context),
          ),
        ],
      ),
    );
  }
}

void _noop() {}
