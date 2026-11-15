// ---------------------------------------------------------------------------
// 无边框窗口外壳
//
// 窗口本身在原生层已经去掉了标题栏（windows/runner/win32_window.cpp 用
// WS_POPUP，不再带系统标题栏）。这里负责两件事：
//
//   1. WindowShell —— 铺满整个窗口的容器，并让「空白处能拖窗口、
//      控件处正常点击」。这两件事同时成立并不平凡，见下面的说明。
//
//   2. WindowControls —— 右上角那几个按钮。返回与关闭左右平行、共享同一顶点。
//
// ---------------------------------------------------------------------------
// 关于拖动区，这里踩过两个坑，写清楚免得以后又改回去。
//
//   【坑一】用 GestureDetector(onPanStart: startDragging) 铺满整窗。
//   以为「控件盖在上面会吃掉手势」就够了。实际不成立 ——
//   拖动层最先进入手势竞技场，用户点链接是「按下 → 抬起」，
//   指针还没移动时两者都在竞技场里僵持；一旦有一点位移 onPanStart 就赢，
//   onTap 永远不触发。结果：页脚所有链接（协议页入口）全部点不动。
//
//   改成 translucent 盖在最上层也不够：translucent 只让下层仍能参与命中，
//   竞技场里仍然是 onPanStart 先认领指针，onTap 还是输。
//
//   【坑二，更隐蔽】改写成「在 onTapDown 里判断落点，落在控件上就把
//   onPanStart 置空」—— 看起来对，实际有两个致命问题：
//
//     a) GestureDetector 只要传了 onTapDown 就会建一个 TapGestureRecognizer。
//        这个识别器什么都没做，却照样进竞技场、照样参与裁决；
//        而它位于上层，会抢先赢得 sweep，把下层 LinkText 的 onTap 判负。
//        实测：仅拖动层覆盖时 taps=0，去掉后 taps=1。
//
//     b) onTapDown 与 build() 是「先 build 后 onTapDown」的顺序。
//        build 时 _overInteractive 还是上一次触摸的旧值，
//        在 onTapDown 里改它并不会触发重建，所以本次手势用的
//        onPanStart 根本不是刚算出来的那个。
//
//   最终做法是「用 Listener 收原始指针事件，手动裁决」：
//   拖动层完全不注册任何手势识别器给它自己，
//   于是它永远不参与竞技场，下层的 Tap 想怎么赢就怎么赢；
//   只有判定「落点在空白处」时，才在 onPointerDown 里现挂一个
//   PanGestureRecognizer 去处理拖动。判断在按下那一刻完成，
//   没有时序错位，也不会有任何识别器凭空抢指针。
// ---------------------------------------------------------------------------
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/auth_controls.dart';

class WindowShell extends StatelessWidget {
  const WindowShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Material 是必须的：TextField / InkWell 等控件要求向上能找到 Material，
    // 否则运行时会直接抛「No Material widget found」并把红色错误块盖在界面上。
    return Material(
      color: AppColors.surface,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // 页面内容放底层：它自己的链接、输入框优先命中
              child,
              // 拖动层盖在最上面，只在「落点不是控件」时才真的拖动
              const WindowDragLayer(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 全窗拖动层：落点在空白处才拖窗口，落在可交互控件上则完全让行。
///
/// 关键设计：本组件**不注册任何手势识别器在自身上**。
/// 只用 [Listener] 旁听指针事件（Listener 不进竞技场），
/// 判定落在空白处时，才临时把 [PanGestureRecognizer] 挂到手势竞技场。
class WindowDragLayer extends StatefulWidget {
  const WindowDragLayer({super.key, this.child});

  /// 可选子级；为空时只负责拖动，不渲染内容
  final Widget? child;

  @override
  State<WindowDragLayer> createState() => _WindowDragLayerState();
}

class _WindowDragLayerState extends State<WindowDragLayer> {
  /// 按下那一刻判定：这个落点下面有没有会消费点击的控件
  bool _overInteractive = false;

  /// 本次按下的 pointer
  int? _activePointer;

  /// 拖动识别器：只在「落点是空白处」时才创建并加入竞技场
  PanGestureRecognizer? _drag;

  @override
  void dispose() {
    _drag?.dispose();
    super.dispose();
  }

  /// 落点下面是否存在会消费点击的 widget。
  ///
  /// hitTest 从整棵树的根开始，一定会先命中本层自己，
  /// 所以这里遍历路径并跳过「本层及其祖先」，
  /// 只看「别人」有没有在这点上放可点击的东西。
  bool _interactiveBelow(Offset globalPosition) {
    final RenderObject? self = context.findRenderObject();
    if (self == null) return false;

    final HitTestResult result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      globalPosition,
      View.of(context).viewId,
    );

    for (final HitTestEntry<HitTestTarget> entry in result.path) {
      final HitTestTarget target = entry.target;
      if (target is! RenderObject) continue;
      final RenderObject ro = target;

      // 跳过本层自己，以及在「自己 → 根」这条链上的所有祖先。
      // 这些是拖动层自身的包裹结构，不代表页面上有控件。
      if (_isSelfOrAncestor(ro, self)) continue;

      if (_looksInteractive(ro)) return true;
    }
    return false;
  }

  /// node 是否就是 self，或者位于「self → 根」的祖先链上
  static bool _isSelfOrAncestor(RenderObject node, RenderObject self) {
    RenderObject? cur = self;
    while (cur != null) {
      if (identical(cur, node)) return true;
      cur = cur.parent;
    }
    return false;
  }

  /// 粗略判断这个 RenderObject 上方是否挂着交互控件。
  ///
  /// RenderPointerListener 是 Listener / RawGestureDetector 的实现类；
  /// GestureDetector、InkWell 最终都会装出一个或多个它。
  /// EditableText 的渲染对象（输入框）单独再判一次，双保险。
  static bool _looksInteractive(RenderObject ro) {
    final String t = ro.runtimeType.toString();
    if (t.contains('PointerListener')) return true;
    if (t.contains('Editable')) return true;
    return false;
  }

  void _onPointerDown(PointerDownEvent event) {
    // 一次只跟一根手指/一个指针，多指时后面的忽略，避免拖拽打架
    if (_activePointer != null) return;

    _overInteractive = _interactiveBelow(event.position);

    // 落在控件上：什么都不挂，彻底退出，把竞技场让给页面
    if (_overInteractive) return;

    _activePointer = event.pointer;

    // 现挂一个拖动识别器。
    // addPointer 内部会：
    //   1) 把 handleEvent 挂到 pointerRouter 上接收后续事件
    //   2) 让本识别器加入该 pointer 的竞技场
    // 因为此刻下层的 onTap 识别器都还没被淘汰，
    // 两者会正常竞争：一指拖动就归拖动，原地抬起就归页面点击。
    final PanGestureRecognizer drag = PanGestureRecognizer()
      ..onStart = (_) => windowManager.startDragging();
    _drag = drag;
    drag.addPointer(event);
  }

  void _endDrag() {
    _activePointer = null;
    final PanGestureRecognizer? drag = _drag;
    _drag = null;
    // dispose 会顺带把自己从 pointerRouter 与竞技场里摘掉，
    // 不需要手写 removeRoute，避免「指针已不存在」的边界处理失误。
    drag?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listener 不参与手势竞技场，纯粹旁听，因此不会抢走下层任何 onTap。
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: (_) => _endDrag(),
      onPointerCancel: (_) => _endDrag(),
      child: widget.child ?? const SizedBox.expand(),
    );
  }
}

/// 右上角窗口控制区：返回 与 关闭 左右平行，共享同一个顶点。
///
/// 做成一个整体组件而不是各页面分别摆放，是为了保证两者永远在同一水平
/// 中心线、同样间距。分别在页面里用 Positioned 摆，很容易出现
/// 「返回偏上两像素」这种一眼能看出来的错位。
///
/// 顺序：返回在左、关闭在右（关闭压在右上角处）。
class WindowControls extends StatelessWidget {
  const WindowControls({super.key, this.onBack, this.onClose});

  /// 为空则不显示返回按钮（登录页没有上一级，只有关闭）
  final VoidCallback? onBack;

  /// 为空时默认直接销毁窗口
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (onBack != null) ...<Widget>[
          CircleBackButton(onTap: onBack!),
          const SizedBox(width: 4),
        ],
        // 关闭用 close()，不能用 destroy()：
        //
        //   destroy() 在 win32 侧只是 PostQuitMessage(0) —— 消息循环立刻退出，
        //   但**窗口本身并没有被销毁**，还挂在屏幕最上层。接下来引擎析构
        //   （FlutterWindow 销毁 → 引擎停机）要走完，窗口才跟着消失。
        //   表现就是「点了关闭，窗口僵在那几百毫秒到一两秒」。
        //
        //   close() 发的是 SC_CLOSE，走正常关闭路径：WM_CLOSE → DestroyWindow，
        //   窗口立刻从屏幕上消失；WM_DESTROY 里 SetQuitOnClose(true) 再
        //   PostQuitMessage 退出进程。引擎析构挪到了窗口消失之后，
        //   用户感知上就是「秒关」。
        //
        // windowManager.close 返回 Future，Dart 允许把任意返回值的函数
        // 赋给 void Function()，返回值自动丢弃。
        CircleCloseButton(onTap: onClose ?? windowManager.close),
      ],
    );
  }
}
