// ---------------------------------------------------------------------------
// 底部图标条（设置 / 个人中心 / 菜单）
//
// 三个图标贴在左栏底部，点任意一个就从右侧推出一个抽屉面板。
//
// 【为什么不用 IconButton】
// 这套 UI 是扁平的 Win32 观感：没有水波纹、没有 48 的最小点击区、没有 Material
// 的图标色调。IconButton 要压制这三样得写一堆覆盖，不如手写一个 26x26 的方块。
//
// 【为什么图标条在左栏里、抽屉却只覆盖右侧】
// 抽屉是「叠在表格上的临时面板」，不是新的一栏。左栏在抽屉打开期间必须仍然
// 可读可点（用户可能边看设置边改参数），所以遮罩与抽屉都只作用在右侧工作区。
// 这也是 MainPage 把 Stack 放在「右栏」而不是整页外面的原因。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';

/// 底部图标条上的三个入口。
///
/// 【每个抽屉的宽度不一样，这是刻意的】
/// 三个面板装的东西差别很大：设置页有五张卡片（通知区一行要塞四件控件），
/// 个人中心只有一个头像 + 两行字 + 一个按钮，菜单只有四个短条目。统一 360
/// 会让后两者右侧空出大半片 —— 头像孤零零挂在左边，菜单像被拉长了。
/// 所以每个 destination 自带一个宽度，由 [drawerWidthOf] 取值。
enum NavDestination {
  settings(
    '设置',
    Icons.settings_outlined,
    Icons.settings,
    kDrawerWidthSettings,
  ),
  profile('个人中心', Icons.person_outline, Icons.person, kDrawerWidthProfile),
  menu('菜单', Icons.menu, Icons.menu_open, kDrawerWidthMenu);

  const NavDestination(this.label, this.icon, this.activeIcon, this.width);

  /// 抽屉标题与 tooltip 文案。
  final String label;

  /// 未选中时的图标。
  final IconData icon;

  /// 选中（抽屉正开着这一项）时的图标。
  final IconData activeIcon;

  /// 这一项的抽屉宽度。按各自内容量定档，见 [kDrawerWidthSettings] 的说明。
  final double width;
}

/// 取某个 destination 的抽屉宽度；null（抽屉关着）时回落到默认档。
///
/// 单独抽一个函数是为了让 DrawerHost 的「收起」分支也有一个合法宽度可用 ——
/// 收起的瞬间仍要按上一次的宽度播退场动画，否则面板会在动画中途变宽/变窄。
double drawerWidthOf(NavDestination? d) => d?.width ?? kDrawerWidthSettings;

/// 左栏底部的三个图标按钮。
class NavBar extends StatelessWidget {
  const NavBar({
    super.key,
    required this.active,
    required this.onSelect,
  });

  /// 当前抽屉对应哪一项；null 表示抽屉关着。
  final NavDestination? active;

  final ValueChanged<NavDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        for (final NavDestination d in NavDestination.values)
          _NavButton(
            destination: d,
            selected: d == active,
            // 再点一次当前项 = 收起抽屉。图标条自身不做开关判断，
            // 交给页面统一处理（页面知道抽屉的动画状态）。
            onTap: () => onSelect(d),
          ),
      ],
    );
  }
}

class _NavButton extends StatefulWidget {
  const _NavButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool selected = widget.selected;
    // 选中：主色；悬停：主色（比选中淡一点靠底色区分）；其余：次要文字色。
    final Color color = selected
        ? WorkColors.primary
        : (_hover ? WorkColors.primary : WorkColors.textHint);

    return Tooltip(
      message: widget.destination.label,
      // 图标条在窗口最底部，tooltip 默认朝下会跑到窗口外面看不见。
      preferBelow: false,
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
            width: kNavButtonSize,
            height: kNavButtonSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // 选中垫 12% 主色、悬停 6%：选中要比悬停明显一档。
              color: selected
                  ? WorkColors.primary.withValues(alpha: 0.12)
                  : (_hover
                        ? WorkColors.primary.withValues(alpha: 0.06)
                        : Colors.transparent),
              borderRadius: BorderRadius.circular(kRadius),
              border: Border.all(
                color: selected ? WorkColors.primary : Colors.transparent,
                width: 1,
              ),
            ),
            // 图标本身也做过渡：选中时从描边图标换成实心图标，硬切会有「跳」感。
            child: AnimatedSwitcher(
              duration: kStateDuration,
              child: Icon(
                selected
                    ? widget.destination.activeIcon
                    : widget.destination.icon,
                key: ValueKey<bool>(selected),
                size: kNavIconSize,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 从右侧滑出的抽屉，带**进出双向**动画。
///
/// 【为什么要包一层 AnimatedSwitcher】
/// 早先只做「进场」：抽屉被条件插入树里时从右侧滑入，但关闭时是直接移除 ——
/// 面板「啪」地消失，与滑入的柔和完全不搭。桌面端这种不对称最容易被感知成
/// 「卡了一下」。
///
/// 现在由 [DrawerHost] 常驻一个 AnimatedSwitcher，开关都走过渡：
/// 进场用 [kDrawerDuration] + [kSlideInCurve]（快起慢收），
/// 退场用 [kDrawerExitDuration] + [kSlideOutCurve]（慢慢启动、加速离开）。
///
/// 【为什么不用 AnimationController】
/// 抽屉只有「开 / 关」两个稳态，没有中途跟随手势的需求。AnimatedSwitcher +
/// TweenAnimationBuilder 就能表达，不必自己管 controller 的 dispose 与 vsync。
/// 将来要做「拖拽边缘跟手」时再换成 controller。
class SlideOutDrawer extends StatelessWidget {
  const SlideOutDrawer({
    super.key,
    required this.title,
    required this.child,
    required this.onClose,
    this.width = kDrawerWidth,
  });

  /// 抽屉标题（取 [NavDestination.label]）。
  final String title;

  final Widget child;

  /// 点右上角关闭按钮。
  final VoidCallback onClose;

  final double width;

  @override
  Widget build(BuildContext context) {
    // 【位移必须作用在 width 宽的盒子上，不能作用在满宽的 Align 上】
    // FractionalTranslation 的倍率是相对**自身**宽度的。如果把它套在满宽的
    // Align 外面，t=1 时会被推出「右栏宽度」那么远（800px），动画前 1/3 全在
    // 屏幕外空跑，看起来像「先卡住再突然出现」。所以这里先把宽度锁成 [width]，
    // 再对这一个盒子做位移 —— 滑入距离恰好等于它自己的宽度，一帧都不浪费。
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: width,
        child: TweenAnimationBuilder<double>(
          // 从 1（完全在右侧外面）跑到 0（就位）。
          tween: Tween<double>(begin: 1, end: 0),
          duration: kDrawerDuration,
          curve: kSlideInCurve,
          builder: (BuildContext context, double t, Widget? child) {
            return FractionalTranslation(
              translation: Offset(t, 0),
              child: Opacity(
                // 滑入的同时淡入：只滑不淡，面板边缘会「切」在表格上显得生硬。
                opacity: 1 - t * 0.6,
                child: child,
              ),
            );
          },
          child: Container(
            decoration: const BoxDecoration(
              color: WorkColors.fieldFill,
              border: Border(
                left: BorderSide(color: WorkColors.border, width: 1),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: kDrawerShadowColor,
                  blurRadius: kDrawerShadowBlur,
                  offset: Offset(kDrawerShadowDx, 0),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _DrawerHeader(title: title, onClose: onClose),
                Expanded(
                  child: SingleChildScrollView(
                    padding: kDrawerContentPadding,
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 抽屉的宿主：负责「开关都带动画」这件事。
///
/// 常驻在右栏的 Stack 里，自己判断该不该显示抽屉。这样关闭时抽屉不是被瞬间
/// 移除，而是先播完退场动画再由 AnimatedSwitcher 摘掉。
///
/// [current] 为 null 表示应当收起；从「有值」变「null」时播退场动画。
///
/// 【宽度按 destination 逐项取，不再是一个统一值】
/// 设置页要 360（五张卡片，通知区一行四件控件），个人中心 260、菜单 200 就够。
/// 宽度取自 [NavDestination.width]，见那里的说明。
///
/// 【width 参数为什么还留着】
/// 给测试与「临时想指定一个宽度」的场合用。传了就用它，不传就按 destination 取。
class DrawerHost extends StatelessWidget {
  const DrawerHost({
    super.key,
    required this.current,
    required this.builder,
    required this.onClose,
    this.width,
  });

  /// 当前要显示的抽屉；null = 收起。
  final NavDestination? current;

  /// 按 destination 造抽屉内容。
  final Widget Function(NavDestination) builder;

  final VoidCallback onClose;

  /// 强制指定宽度。null（默认）= 按 [NavDestination.width] 逐项取。
  final double? width;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: kDrawerExitDuration,
      reverseDuration: kDrawerExitDuration,
      switchInCurve: kSlideInCurve,
      switchOutCurve: kSlideOutCurve,
      // 退场时让旧面板「继续往右走」而不是原地淡出：
      // 默认的 FadeTransition 会让它留在原地渐隐，看起来像「没关掉」。
      transitionBuilder: (Widget child, Animation<double> anim) {
        // anim 在进场时 0→1、退场时 1→0，两种方向都映射成「右侧偏移」。
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        );
      },
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
        // 只留一个面板：进出重叠时后一个盖住前一个，不会出现两层抽屉并排。
        return Stack(
          alignment: Alignment.centerRight,
          children: <Widget>[
            ...previousChildren,
            ?currentChild,
          ],
        );
      },
      child: current == null
          // 用 SizedBox.shrink 而不是 null：AnimatedSwitcher 需要「有东西」才肯
          // 播退场 —— 传 null 它会立刻摘掉旧 child，退场动画就没有了。
          ? const SizedBox.shrink(key: ValueKey<String>('drawer-closed'))
          : SlideOutDrawer(
              key: ValueKey<NavDestination>(current!),
              title: current!.label,
              onClose: onClose,
              width: width ?? current!.width,
              child: builder(current!),
            ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kDrawerHeaderHeight,
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: const BoxDecoration(
        color: WorkColors.panel,
        border: Border(bottom: BorderSide(color: WorkColors.border, width: 1)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: kFontTitle,
                fontWeight: FontWeight.w600,
                color: WorkColors.textPrimary,
                fontFamily: kFontFamily,
                fontFamilyFallback: kFontFallback,
                letterSpacing: 0.4,
              ),
            ),
          ),
          _DrawerCloseButton(onTap: onClose),
        ],
      ),
    );
  }
}

class _DrawerCloseButton extends StatefulWidget {
  const _DrawerCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_DrawerCloseButton> createState() => _DrawerCloseButtonState();
}

class _DrawerCloseButtonState extends State<_DrawerCloseButton> {
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
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover
                ? WorkColors.primary.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(kTitleButtonRadius),
          ),
          child: Icon(
            Icons.close,
            size: 15,
            color: _hover ? WorkColors.primary : WorkColors.textHint,
          ),
        ),
      ),
    );
  }
}
