// ---------------------------------------------------------------------------
// 右侧抽屉的三块内容（设置 / 个人中心 / 菜单）
//
// 这三个面板都是「只画界面、动作留空」—— 与左栏卡片的定位一致：本工程是界面
// 还原，设置项存不存盘、菜单项点下去做什么，都要等接入真实业务时再填。
//
// 【为什么三个面板放一个文件】
// 每个都只有几十行、彼此没有依赖、且都只被 drawer_content 的分支引用一次。
// 拆成三个文件会让「改一个设置项」变成「先找对文件」；放一起反而一眼看全。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/panel_controls.dart';

/// 抽屉里的一行：左边文案、右边控件。
class _DrawerRow extends StatelessWidget {
  const _DrawerRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 78,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: kFontBody,
                color: WorkColors.textPrimary,
                fontFamily: kFontFamily,
                fontFamilyFallback: kFontFallback,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 分组小标题（抽屉内部用，比左栏的 SectionLabel 小一档、不用主色）。
class _DrawerSection extends StatelessWidget {
  const _DrawerSection({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: kFontHint,
          fontWeight: FontWeight.w600,
          color: WorkColors.textMuted,
          fontFamily: kFontFamily,
          fontFamilyFallback: kFontFallback,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 设置
// ---------------------------------------------------------------------------

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.autoStart,
    required this.notify,
    required this.retry,
    required this.running,
    required this.concurrency,
    required this.onAutoStartChanged,
    required this.onNotifyChanged,
    required this.onRetryChanged,
  });

  final bool autoStart;
  final bool notify;
  final bool retry;

  /// 只读回显用：当前是否在跑、并发数是多少。
  final bool running;
  final String concurrency;

  final ValueChanged<bool> onAutoStartChanged;
  final ValueChanged<bool> onNotifyChanged;
  final ValueChanged<bool> onRetryChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _DrawerSection(text: '运行'),
        CheckBoxRow(
          label: '开机自动启动',
          value: autoStart,
          onChanged: onAutoStartChanged,
        ),
        CheckBoxRow(
          label: '失败自动重试',
          value: retry,
          onChanged: onRetryChanged,
        ),
        const _DrawerSection(text: '提示'),
        CheckBoxRow(
          label: '操作完成时提示',
          value: notify,
          onChanged: onNotifyChanged,
        ),
        const _DrawerSection(text: '当前状态'),
        // 只读回显：让设置面板有一个「能看到东西」的落点，而不是纯开关列表。
        _DrawerRow(
          label: '运行模式',
          child: Text(
            running ? '运行中' : '已停止',
            style: TextStyle(
              fontSize: kFontBody,
              fontWeight: FontWeight.w600,
              color: running ? WorkColors.running : WorkColors.textMuted,
              fontFamily: kFontFamily,
              fontFamilyFallback: kFontFallback,
            ),
          ),
        ),
        _DrawerRow(
          label: '并发数',
          child: Text(
            concurrency,
            style: const TextStyle(
              fontSize: kFontBody,
              color: WorkColors.textPrimary,
              fontFamily: kFontFamily,
              fontFamilyFallback: kFontFallback,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 个人中心
// ---------------------------------------------------------------------------

class ProfilePanel extends StatelessWidget {
  const ProfilePanel({
    super.key,
    required this.account,
    required this.onLogout,
  });

  /// 当前登录账号（空串表示未登录）。
  final String account;

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final bool loggedIn = account.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            // 头像：没有真实图片，用首字母占位。
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: WorkColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: WorkColors.primary, width: 1),
              ),
              child: Text(
                loggedIn ? account.characters.first.toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: WorkColors.primary,
                  fontFamily: kFontFamily,
                  fontFamilyFallback: kFontFallback,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    loggedIn ? account : '未登录',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: kFontTitle,
                      fontWeight: FontWeight.w600,
                      color: WorkColors.textPrimary,
                      fontFamily: kFontFamily,
                      fontFamilyFallback: kFontFallback,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    loggedIn ? '已登录' : '请先在左栏登录',
                    style: const TextStyle(
                      fontSize: kFontHint,
                      color: WorkColors.textMuted,
                      fontFamily: kFontFamily,
                      fontFamilyFallback: kFontFallback,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        PanelButton(
          label: '退出登录',
          height: kCompactButtonHeight,
          // 未登录时没有可退的 —— 用 onPressed: null 表达禁用。
          onPressed: loggedIn ? onLogout : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 菜单
// ---------------------------------------------------------------------------

/// 菜单项：图标 + 文案 + 回调。
class _MenuItem extends StatefulWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
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
          height: kRowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: _hover
                ? WorkColors.primary.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(kRadius),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                widget.icon,
                size: kNavIconSize,
                color: _hover ? WorkColors.primary : WorkColors.textHint,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: kFontBody,
                    color: _hover
                        ? WorkColors.primary
                        : WorkColors.textPrimary,
                    fontFamily: kFontFamily,
                    fontFamilyFallback: kFontFallback,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MenuPanel extends StatelessWidget {
  const MenuPanel({
    super.key,
    required this.onOpenDocs,
    required this.onOpenLogs,
    required this.onCheckUpdate,
    required this.onAbout,
  });

  final VoidCallback onOpenDocs;
  final VoidCallback onOpenLogs;
  final VoidCallback onCheckUpdate;
  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _MenuItem(
          icon: Icons.menu_book_outlined,
          label: '使用说明',
          onTap: onOpenDocs,
        ),
        _MenuItem(
          icon: Icons.description_outlined,
          label: '运行日志',
          onTap: onOpenLogs,
        ),
        _MenuItem(
          icon: Icons.system_update_alt,
          label: '检查更新',
          onTap: onCheckUpdate,
        ),
        _MenuItem(
          icon: Icons.info_outline,
          label: '关于',
          onTap: onAbout,
        ),
      ],
    );
  }
}
