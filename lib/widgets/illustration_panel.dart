// ---------------------------------------------------------------------------
// 左侧插画面板（占窗口宽度 40%，对应参考图 0-295 / 736）
//
// 图片来源：assets/images/side.png（替换文件即可，不用改代码）
// 在插画之上叠加一层飘落花瓣，花瓣用纯 Flutter 绘制，不依赖图片。
// ---------------------------------------------------------------------------
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';

class IllustrationPanel extends StatefulWidget {
  const IllustrationPanel({super.key});

  /// 插画资源路径。把图片放到这个位置就行。
  static const String imagePath = 'assets/images/side.png';

  /// 花瓣飘落的开关。
  ///
  /// 花瓣是无限循环动画（30 秒一圈，repeat() 永不结束）。
  /// 在 widget 测试里这会让 pumpAndSettle 永远等不到「没有待处理帧」，
  /// 直接超时失败——而超时是整套测试一起挂，很难看出跟花瓣有关。
  /// 所以测试启动时把它关掉：静态画一帧就停，动画本身在生产环境照常跑。
  @visibleForTesting
  static bool petalsEnabled = true;

  @override
  State<IllustrationPanel> createState() => _IllustrationPanelState();
}

class _IllustrationPanelState extends State<IllustrationPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// 固定种子，保证每次运行的花瓣分布一致，不会看起来乱跳
  late final List<_Petal> _petals;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    );
    if (IllustrationPanel.petalsEnabled) {
      _controller.repeat();
    } else {
      // 关闭时停在一个固定的进度上：花瓣仍然画出来（画面不空），
      // 但不再有排不完的帧，pumpAndSettle 能正常收敛。
      _controller.value = 0.35;
    }

    final math.Random rnd = math.Random(20260921);
    _petals = List<_Petal>.generate(18, (int i) {
      return _Petal(
        // 水平起点
        x: rnd.nextDouble(),
        // 相位错开，避免所有花瓣同步下落
        phase: rnd.nextDouble(),
        // 每片花瓣下落速度略有差异
        speed: 0.55 + rnd.nextDouble() * 0.8,
        // 尺寸 5 - 13
        size: 5 + rnd.nextDouble() * 8,
        // 左右摆动幅度
        sway: 12 + rnd.nextDouble() * 26,
        // 自旋速度
        spin: (rnd.nextDouble() - 0.5) * 2.2,
        // 透明度，让花瓣有远近层次
        opacity: 0.35 + rnd.nextDouble() * 0.5,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(5),
        bottomLeft: Radius.circular(5),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _buildImageLayer(),
          // 花瓣层
          //
          // RepaintBoundary 是这一层的关键，不能省：
          // 花瓣每帧都在动，而 CustomPaint 自己没有绘制边界，这次重绘会一路
          // 向上传到最近的 RepaintBoundary —— 也就是整页。结果是每秒 60 次
          // 把下面那张 40% 宽的插画、整个表单区一起重画一遍。
          // 加上边界之后，重绘被限制在这块矩形里，插画层完全不参与。
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, Widget? child) {
                return CustomPaint(
                  painter: _PetalPainter(
                    petals: _petals,
                    progress: _controller.value,
                  ),
                  size: Size.infinite,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 插画层。图片缺失时不让整个界面崩掉，而是退回到绿底 + 提示。
  Widget _buildImageLayer() {
    return Image.asset(
      IllustrationPanel.imagePath,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
        return const _ImagePlaceholder();
      },
    );
  }
}

/// 图片没放进来时的占位：绿色渐变 + 说明文字
class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFC9D97A), Color(0xFFA8BE4E)],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.image_outlined,
                size: 34,
                color: Colors.white.withValues(alpha: 0.9),
              ),
              const SizedBox(height: 12),
              Text(
                '把插画放到\nassets/images/side.png',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.7,
                  color: Colors.white.withValues(alpha: 0.95),
                  fontFamily: kFontFamily,
                  fontFamilyFallback: kFontFallback,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 花瓣
// ---------------------------------------------------------------------------

class _Petal {
  _Petal({
    required this.x,
    required this.phase,
    required this.speed,
    required this.size,
    required this.sway,
    required this.spin,
    required this.opacity,
  });

  /// 水平起点，0-1 归一化
  final double x;

  /// 动画相位偏移，0-1
  final double phase;

  /// 下落速度倍率
  final double speed;

  /// 花瓣尺寸
  final double size;

  /// 左右摆动像素幅度
  final double sway;

  /// 自旋速度
  final double spin;

  /// 不透明度
  final double opacity;

  /// 花瓣轮廓。
  ///
  /// 形状只由 [size] 决定，而 size 构造后就固定了，所以整条贝塞尔路径
  /// 只需要算一次。放在这里而不是 paint() 里，是因为 paint() 每帧都会跑：
  /// 原来每帧要为 18 片花瓣各建一个 Path 并重走一遍贝塞尔曲线。
  late final Path path = Path()
    ..moveTo(0, -size)
    ..quadraticBezierTo(size * 0.85, -size * 0.25, 0, size)
    ..quadraticBezierTo(-size * 0.85, -size * 0.25, 0, -size)
    ..close();
}

class _PetalPainter extends CustomPainter {
  _PetalPainter({required this.petals, required this.progress});

  final List<_Petal> petals;

  /// 0-1 的循环进度
  final double progress;

  /// 两支画笔，**实例字段**而不是 static。
  ///
  /// 早先是 static final：理由「避免每帧重新分配」。但 static 意味着全进程只有
  /// 一份，而 paint() 会改它的 color —— 登录页与注册页在 AnimatedSwitcher 里
  /// 交叉淡入时，**两个 _PetalPainter 实例会同时存在**（一个在退场、一个在
  /// 入场），它们共享同一支 Paint。绘制虽然是同步的，但两个 painter 的绘制
  /// 交错发生，于是 B 的 alpha 会覆盖 A 刚设好的值 —— 花瓣透明度在两个页面上
  /// 互相串。单实例时看不出来，加页面切换才暴露。
  ///
  /// 现在改成实例字段：每个 painter 每帧各分配两支（18×2 支笔的对象创建相对
  /// 一次 canvas.drawPath 的开销可以忽略，且 Dart 的短命对象分配是指针碰撞）。
  /// 换来的是「任何时刻都不会跨实例串色」这个确定性质。
  final Paint _fill = Paint()..style = PaintingStyle.fill;
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.7;

  @override
  void paint(Canvas canvas, Size size) {
    for (final _Petal p in petals) {
      // 每片花瓣有自己的相位，整体做 y 轴循环
      final double t = (progress * p.speed + p.phase) % 1.0;

      // 竖直位置：从顶部 -8% 飘到 108%
      final double dy = (t * 1.16 - 0.08) * size.height;

      // 水平位置：基础位置 + 正弦摆动
      final double baseX = p.x * size.width;
      final double dx =
          baseX + math.sin((t * 2 * math.pi) + p.phase * 6) * p.sway;

      // 越往下越淡，模拟飘远
      final double fade = t < 0.12
          ? t / 0.12
          : (t > 0.85 ? (1 - t) / 0.15 : 1.0);

      final double alpha = (p.opacity * fade).clamp(0.0, 1.0);
      if (alpha <= 0.01) continue;

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(t * p.spin * 2 * math.pi);

      // 花瓣形状：一片白色椭圆，用两条二次贝塞尔勾出尖端。
      // 路径在 _Petal 里已经算好并缓存，这里直接用。
      // 白色花瓣 + 一点点绿边，和插画里的白花呼应。
      _fill.color = Colors.white.withValues(alpha: alpha);
      canvas.drawPath(p.path, _fill);

      _stroke.color = const Color(0xFF6FA83C).withValues(alpha: alpha * 0.45);
      canvas.drawPath(p.path, _stroke);

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _PetalPainter old) {
    return old.progress != progress || old.petals != petals;
  }
}
