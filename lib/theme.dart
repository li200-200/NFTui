// ---------------------------------------------------------------------------
// 配色、字体、尺寸 —— 全工程唯一的取值来源
//
// 这里的每个色值 / 尺寸都是从参考工程 pigeon_app 的工作台实测值抄下来的，
// 不是目测调的。改这里的任何一个数字，整个工作台的观感都会跟着变，
// 所以：**不要在别处写死色值或尺寸**，加常量加在这个文件里。
//
// 两套命名并存是刻意的：
//   · AppColors —— 全局色板（验证页与工作台共用的那部分也在这里）；
//   · WorkColors —— 工作台语义别名，全部指向 AppColors，单一来源不会各自漂移。
// 本任务只做工作台界面，但保留两层命名是为了与参考工程的文件结构对齐 ——
// 以后要把验证页搬过来时不用再改一遍引用。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

/// 全局色板。
class AppColors {
  const AppColors._();

  // ---- 主色 ----

  /// 主操作绿：主按钮描边 / 文字、选中态、聚焦边框、滚动条。
  static const Color primary = Color(0xFF3AAF9F);

  /// 按下态；同时是 SnackBar 底色。
  static const Color primaryDark = Color(0xFF2E9184);

  /// 主色 12% 透明：选中行底、文字选区、聚焦外发光。
  ///
  /// 0x1F = 31/255 ≈ 12.2%，四舍五入到 12% —— 与设计令牌一致。
  static const Color primarySoft = Color(0x1F3AAF9F);

  /// 纯绿文字：分区小标题、成功状态文字。
  static const Color brand = Color(0xFF008000);

  // ---- 中性色 ----

  /// 页面底色。
  static const Color surface = Color(0xFFFCFCFE);

  /// 左栏面板底、GroupBox 内底、禁用按钮底。
  static const Color panel = Color(0xFFF5F6F7);

  /// 输入框 / 下拉框 / 表格底（工作台是白底输入框，不是验证页的灰底）。
  static const Color fieldFill = Color(0xFFFFFFFF);

  /// 输入框聚焦、下拉框悬停。
  static const Color fieldFillFocused = Color(0xFFF2F8F7);

  /// 1px 硬边框、表格线、分割线。
  static const Color border = Color(0xFFD8DBDE);

  /// 表头底。
  static const Color headerFill = Color(0xFFEFF3F2);

  /// 表格斑马纹（奇数行）。
  static const Color rowAlt = Color(0xFFF8FAFA);

  /// 主文字。
  static const Color textPrimary = Color(0xFF2B2B2B);

  /// 次要文字（输入框提示、未选中标签）。
  static const Color textHint = Color(0xFF7A7A7A);

  /// 辅助文字（禁用态、占位说明）。
  static const Color textMuted = Color(0xFF9A9A9A);

  // ---- 语义色 ----

  /// 窗口关闭按钮的红。
  static const Color danger = Color(0xFFE0525A);

  /// 校验失败的红。比 danger 更暗一点，压在浅色输入框上更稳。
  static const Color error = Color(0xFFD64545);

  /// 状态：运行中。
  static const Color running = Color(0xFF2E9184);

  /// 状态：等待 / 空闲。
  static const Color idle = Color(0xFF9A9A9A);

  /// 状态：有订单。
  ///
  /// 用橙而不是红/绿：它既不是失败也不是成功，是一个「需要人看一眼」的提示态。
  static const Color warning = Color(0xFFD98324);
}

/// 工作台的语义别名。全部指向 [AppColors]，不引入新的色值。
class WorkColors {
  const WorkColors._();

  static const Color primary = AppColors.primary;
  static const Color primaryDark = AppColors.primaryDark;
  static const Color primarySoft = AppColors.primarySoft;
  static const Color brand = AppColors.brand;

  static const Color surface = AppColors.surface;
  static const Color panel = AppColors.panel;
  static const Color fieldFill = AppColors.fieldFill;
  static const Color fieldFillFocused = AppColors.fieldFillFocused;
  static const Color border = AppColors.border;
  static const Color headerFill = AppColors.headerFill;
  static const Color rowAlt = AppColors.rowAlt;

  static const Color textPrimary = AppColors.textPrimary;
  static const Color textHint = AppColors.textHint;
  static const Color textMuted = AppColors.textMuted;

  static const Color danger = AppColors.danger;
  static const Color error = AppColors.error;
  static const Color running = AppColors.running;
  static const Color idle = AppColors.idle;
  static const Color warning = AppColors.warning;
}

// ---------------------------------------------------------------------------
// 字体
// ---------------------------------------------------------------------------

/// 中文字体。Flutter 桌面端默认字体渲染中文一般，这里显式指定微软雅黑。
const String kFontFamily = 'Microsoft YaHei';

/// 字体回退链：机器上没装雅黑时依次退到这些，避免掉进方框字体。
const List<String> kFontFallback = <String>[
  '微软雅黑',
  'Microsoft YaHei UI',
  'PingFang SC',
  'SimHei',
];

/// 正文字号（表格单元格、输入框、按钮、勾选文字、分区标题）。
const double kFontBody = 12.5;

/// 表头 / 主标题。
const double kFontTitle = 13;

/// 提示（输入框 hint、tooltip）。
const double kFontHint = 12;

// ---------------------------------------------------------------------------
// 尺寸
// ---------------------------------------------------------------------------

/// 工作台所有输入框 / 按钮 / 下拉统一高。
const double kRowHeight = 30;

/// 行与行之间的间隙。
const double kRowGap = 7;

/// 面板内边距（窗口内容区四边）。
const double kPanelPadding = 12;

/// 左栏固定宽度。来自 .ui 的 211，取 212 保证中文标签不挤。
///
/// 【滚动条不再固定占用这 212】
/// 早先 [kPanelWidth] 是 212 但滚动条无条件占 8，卡片实际只有 204 ——
/// 既比设计的 211 窄，左右内边距也不对称（左 12 / 右 20）。
///
/// 现在滚动条只在真的需要滚动时才让出 [kLeftPanelScrollGutter]：
///   · 放得下（设计尺寸 1048x682）→ 卡片 212，与设计一致、左右对称；
///   · 放不下（窗口压到最小 880x620）→ 卡片 204，让出 8 给滚动条。
/// 212 这个数本身不用动，改的是「要不要让位」这件事。
const double kPanelWidth = 212;

/// 左栏滚动条让出的宽度。
///
/// 只在「真的需要滚动」时才让出（见 main_page.dart 的 _LeftPanelScroller）：
/// 不需要滚动时不占位，卡片就能用满 220。
const double kLeftPanelScrollGutter = 8;

/// 左栏所有「标签格 + 输入格」的标签格宽度。
///
/// 【为什么统一成一个值】
/// .ui 里是按绝对坐标摆的：账户 / 密码的标签 31、支付密码 51、选项区 41、
/// 信息区 51 —— 于是四个输入格的左边界落在四条不同的竖线上，看着像没对齐。
/// 绝对坐标本身是要丢弃的信息，这里改成统一 60：
///   · 最长标签「支付密码」四个字约 50px，60 放得下且不必缩字；
///   · 左栏三张卡片的输入框左边界落在同一条竖线上，纵向扫一眼是整齐的。
const double kLabelWidth = 60;

/// 工作台圆角统一 3：输入框外侧两角、按钮、下拉、表格外框。
const double kRadius = 3;

/// 标题条按钮圆角 4（比工作台控件大一档，38 高的条上更协调）。
const double kTitleButtonRadius = 4;

/// 标题条高。
const double kTitleBarHeight = 38;

/// 表头高。
const double kHeaderHeight = 40;

/// 数据行高（ListView 的 itemExtent）。
const double kRowItemExtent = 34;

/// 滚动条粗细 / 圆角。
const double kScrollThickness = 6;
const double kScrollRadius = 3;

/// 小号按钮高度（「查询」这类小按钮）。取自 .ui 里 pushButton_cx 的 41x21。
const double kSmallButtonHeight = 21;

/// 小号按钮宽度（同上）。
const double kSmallButtonWidth = 41;

/// 紧凑按钮高度。来自 .ui 里 QPushButton 的 23 —— 「发送 / 登录 / 加入修改」
/// 三处都是这个高度，比 kRowHeight 矮 7px，压在输入框下方更紧凑。
const double kCompactButtonHeight = 23;

/// 扁平标签条高（QTabWidget 的标签行）。
const double kTabBarHeight = 34;

/// 选中标签底部的下划线粗细。
const double kTabUnderline = 2;

/// 标签左右内边距。
const double kTabPadding = 18;

/// 卡片（PanelGroupBox）之间的垂直间距。
const double kCardGap = 12;

/// 卡片内边距：上 10 / 下 12（下方留多一点，压住最后一行的边框）。
const EdgeInsets kGroupBoxPadding = EdgeInsets.fromLTRB(10, 10, 10, 12);

/// 分区标题与它下方第一个控件之间的间距。
const double kSectionGap = 6;

/// 按钮行上方那一点点额外间距。
///
/// 按钮与输入框之间要「断开」一点，否则视觉上会以为按钮也是某个输入框的右格。
const double kPreButtonGap = 8;

// ---------------------------------------------------------------------------
// 紧凑档位
//
// 【为什么需要它】
// 左栏四张卡片在 1048x682 下用常规间距铺满（不出现滚动条）。但窗口压到
// 最小 880x620 时，可用高度少了 62px，而控件高度（30）与字号（12.5）都是硬令牌
// 不能动 —— 能收的只有「间距」。
//
// 这里只压缩空白：行间距、卡片间距、卡片内边距、分区标题间距。控件本身一个
// 像素都不缩，所以小窗口下仍然是同一套观感，只是更紧凑。
// ---------------------------------------------------------------------------

/// 紧凑档：行间距。
const double kCompactRowGap = 5;

/// 紧凑档：卡片间距。
const double kCompactCardGap = 5;

/// 紧凑档：分区标题与首个控件的间距。
const double kCompactSectionGap = 3;

/// 紧凑档：卡片内边距。
const EdgeInsets kCompactGroupBoxPadding = EdgeInsets.fromLTRB(10, 6, 10, 8);

/// 紧凑档：按钮行上方间距。
const double kCompactPreButtonGap = 4;

// ---------------------------------------------------------------------------
// 密排档（左栏四张卡片仍装不下时使用）
//
// 只压空白，控件高度与字号不动。四张卡片一共 9 行控件 + 3 行按钮 + 4 个分区
// 标题，硬令牌合计约 411px；设计窗口扣掉标题条后的可用高度是 620，能分给空白
// 的只有 200 出头，还要扣掉卡片边框与内边距 —— 这一档就是把它用到极限。
// ---------------------------------------------------------------------------

/// 密排档：行间距。
const double kDenseRowGap = 2;

/// 密排档：卡片间距。
const double kDenseCardGap = 1;

/// 密排档：分区标题与首个控件的间距。
const double kDenseSectionGap = 1;

/// 密排档：卡片内边距。
///
/// 上下收到 2 / 2：底部图标条（[kNavButtonSize] + [kNavBarGap] = 32）要从左栏
/// 高度里让出位置，四张卡片各收 2px 才能补上这 32。
const EdgeInsets kDenseGroupBoxPadding = EdgeInsets.fromLTRB(8, 2, 8, 2);

/// 密排档：按钮行上方间距。
const double kDensePreButtonGap = 2;

// ---------------------------------------------------------------------------
// 底部图标条 + 右侧抽屉
// ---------------------------------------------------------------------------

/// 底部图标条里每个按钮的边长。
const double kNavButtonSize = 26;

/// 底部图标条里图标本身的边长。
const double kNavIconSize = 16;

/// 底部图标条与上方卡片之间的间距。
const double kNavBarGap = 6;

/// 右侧抽屉的宽度。
///
/// 只覆盖右侧工作区，不碰左栏 —— 抽屉是「叠在表格上的临时面板」，不是新的一栏。
const double kDrawerWidth = 360;

/// 抽屉滑出 / 收回的时长。
///
/// 300ms 是刻意的「慢」：面板从右边缘推出来，慢一点才看得出它是「滑」而不是
/// 「闪」。再快（<200ms）在桌面端会像掉帧。
const Duration kDrawerDuration = Duration(milliseconds: 300);

/// 抽屉收起的时长。
///
/// 比展开短 1/4：退出动画在感知上应该比进入快 —— 用户点「关闭」时已经决定了，
/// 再让他等满 300ms 就显得迟钝。展开则相反，需要时间让眼睛跟上它从哪来。
const Duration kDrawerExitDuration = Duration(milliseconds: 220);

/// 抽屉打开时压在右侧工作区上的遮罩浓度。
///
/// 只压右侧，左侧完全不加遮罩 —— 左栏（登录 / 信息 / 选项 / 操作）在抽屉打开
/// 期间仍然可读可点。
const double kDrawerScrimAlpha = 0.18;

/// 抽屉左侧投影的颜色与形状。
///
/// 抽屉是浮在表格之上的，没有投影会看成「表格被压窄了」。阴影只往左打，
/// 右侧贴着窗口边缘不需要。
const Color kDrawerShadowColor = Color(0x1A000000);
const double kDrawerShadowBlur = 16;
const double kDrawerShadowDx = -4;

/// 抽屉标题栏高度（与工作台控件同一套 30/40 节奏）。
const double kDrawerHeaderHeight = 40;

/// 抽屉内容区的内边距。
const EdgeInsets kDrawerContentPadding = EdgeInsets.fromLTRB(14, 12, 14, 14);

// ---------------------------------------------------------------------------
// 交互手感（动效时长与曲线）
//
// 【为什么要集中定义】
// 桌面端的「丝滑」几乎全在时长上：悬停太快像闪、太慢像卡；按下要立刻响应，
// 松开要有回弹感。这些数字散落在各控件里就会互相不一致 —— 悬停 120ms、按下
// 80ms、选中 150ms 摆在一起，用户说不出哪里怪，但就是觉得不整齐。
//
// 这里按「动作类型」而不是「控件」来定义：同类反馈用同一个时长，整机手感才统一。
// ---------------------------------------------------------------------------

/// 悬停 / 焦点这类「轻反馈」的过渡时长。
///
/// 90ms：鼠标划过时底色几乎跟手就变，但仍有一帧以上的过渡，不是硬切。
const Duration kHoverDuration = Duration(milliseconds: 90);

/// 按下 / 松开这类「重反馈」的过渡时长。
///
/// 60ms：按下必须「立刻」有回应。超过 100ms 会被感知成「点了没反应」。
const Duration kPressDuration = Duration(milliseconds: 60);

/// 状态切换（选中行、标签下划线、勾选框）的过渡时长。
///
/// 150ms：比悬停慢一档，让用户看清「什么变成了什么」，而不是一闪而过。
const Duration kStateDuration = Duration(milliseconds: 150);

/// 滑入类动效（抽屉、菜单）的曲线：快起慢收。
///
/// easeOutCubic 的起始速度约为匀速的 3 倍，收尾极缓 —— 视觉上就是「一下推出来
/// 然后轻轻贴住」，这正是面板滑入该有的手感。
const Curve kSlideInCurve = Curves.easeOutCubic;

/// 滑出 / 收起类动效的曲线。
///
/// easeInCubic 与滑入相反：慢慢启动、加速离开。收起时用户注意力已经转移，
/// 让它「快点走开」比「温柔退场」更不拖沓。
const Curve kSlideOutCurve = Curves.easeInCubic;

/// 左栏的一整套垂直间距。常规 / 紧凑 / 密排三档，由页面的 LayoutBuilder 选用。
///
/// 做成值对象而不是一堆 if：各间距之间存在比例关系（紧凑档收到常规档的六成、
/// 密排档收到四成左右），集中在一处才好整体调，也不会出现「改了一个忘了另一个」。
class PanelMetrics {
  const PanelMetrics({
    required this.rowGap,
    required this.cardGap,
    required this.sectionGap,
    required this.groupBoxPadding,
    required this.preButtonGap,
  });

  final double rowGap;
  final double cardGap;
  final double sectionGap;
  final EdgeInsets groupBoxPadding;
  final double preButtonGap;

  /// 常规档：左栏内容装得下时优先用它。
  static const PanelMetrics normal = PanelMetrics(
    rowGap: kRowGap,
    cardGap: kCardGap,
    sectionGap: kSectionGap,
    groupBoxPadding: kGroupBoxPadding,
    preButtonGap: kPreButtonGap,
  );

  /// 紧凑档：常规档装不下时退到这一档。
  static const PanelMetrics compact = PanelMetrics(
    rowGap: kCompactRowGap,
    cardGap: kCompactCardGap,
    sectionGap: kCompactSectionGap,
    groupBoxPadding: kCompactGroupBoxPadding,
    preButtonGap: kCompactPreButtonGap,
  );

  /// 密排档：紧凑档也装不下时退到这一档。
  ///
  /// 【为什么需要第三档】
  /// 左栏从三张卡片变成四张（.ui 新增「操作」区）之后，控件高度本身就把总高
  /// 顶过了设计窗口的可用高度：四张卡片里一共 9 行控件（行高 30）+ 3 行按钮
  /// （23）+ 4 个分区标题（18），仅这些硬令牌就是 270 + 69 + 72 = 411，剩下的
  /// 才是可以压缩的空白。常规档的空白约 100px，紧凑档约 70px，都还不够 ——
  /// 只有把空白再收到 40px 上下，才能让四张卡片在 620 的可用高度里全部露出。
  ///
  /// 这一档仍然只压空白：控件高度与字号一个像素都不动。
  static const PanelMetrics dense = PanelMetrics(
    rowGap: kDenseRowGap,
    cardGap: kDenseCardGap,
    sectionGap: kDenseSectionGap,
    groupBoxPadding: kDenseGroupBoxPadding,
    preButtonGap: kDensePreButtonGap,
  );

  /// 三档由宽到紧的候选顺序。选档时从头试，第一个装得下的就是它。
  static const List<PanelMetrics> byDescendingSpace = <PanelMetrics>[
    normal,
    compact,
    dense,
  ];

  /// 本档下左栏内容的总高度（含卡片间距）。
  ///
  /// 这个数字不是算出来的近似值，而是「四张卡片各自的实际高度之和」——
  /// 页面的 LayoutBuilder 用它来决定该用哪一档。
  /// 各卡片高度见 [loginCardHeight] / [infoCardHeight] / [optionCardHeight] /
  /// [actionCardHeight]。
  double get contentHeight =>
      loginCardHeight +
      infoCardHeight +
      optionCardHeight +
      actionCardHeight +
      cardGap * 3;

  /// 分区标题一行的高度（12.5 号字，行高由字体度量决定）。
  ///
  /// 取 18 而不是 17：微软雅黑 12.5 号的 ascent+descent 约 17.4，向上取整到 18
  /// 才能保证 [contentHeight] 不会低估 —— 低估会导致「判定为放得下、实际溢出」。
  static const double sectionLabelHeight = 18;

  /// 单个 LabeledField / PanelDropdown 行高（= kRowHeight）。
  static const double fieldRowHeight = kRowHeight;

  double get loginCardHeight =>
      groupBoxPadding.vertical +
      sectionLabelHeight +
      sectionGap +
      // 账户 / 密码 / 支付密码 三行 + 两个行间距
      fieldRowHeight * 3 +
      rowGap * 2 +
      preButtonGap +
      // 底部「发送 / 登录」一行
      kCompactButtonHeight;

  double get infoCardHeight =>
      groupBoxPadding.vertical +
      sectionLabelHeight +
      sectionGap +
      // 顶部「下拉 + 查询」
      fieldRowHeight +
      rowGap +
      // key 输入框（.ui 里 lineEdit_cpxx_2，紧跟在顶部下拉下面）
      fieldRowHeight +
      rowGap +
      // 藏品信息 / 藏品Id / 数量 / 价格 四行 + 三个行间距
      fieldRowHeight * 4 +
      rowGap * 3 +
      preButtonGap +
      // 底部「加入修改」
      kCompactButtonHeight;

  double get optionCardHeight =>
      groupBoxPadding.vertical +
      sectionLabelHeight +
      sectionGap +
      // 功能 / 方式 / 支付 三行 + 两个行间距
      fieldRowHeight * 3 +
      rowGap * 2;

  /// 「操作」卡片：并发一行 + 「开始 / 结束」一行。
  ///
  /// .ui 里是 groupBox（y=480，211x81）：并发输入框在 y=19、两个按钮在 y=50，
  /// 两者之间没有额外的分组标题 —— 结构与「登录区」那张卡片同构。
  double get actionCardHeight =>
      groupBoxPadding.vertical +
      sectionLabelHeight +
      sectionGap +
      // 并发
      fieldRowHeight +
      preButtonGap +
      // 开始 / 结束
      kCompactButtonHeight;
}

/// 设计窗口尺寸，取自 .ui 的 geometry（1048x682）。
/// 原生层 windows/runner/main.cpp 里也有同一组数字，两处必须保持一致。
const double kDesignWidth = 1048;
const double kDesignHeight = 682;

/// 窗口最小尺寸。比设计尺寸小一档：左栏此时转为可滚动，右侧表格按比例收窄。
const double kMinWidth = 880;
const double kMinHeight = 620;

/// 窗口标题（.ui 里的 windowTitle，原样保留，不要改成别的）。
const String kWindowTitle = '阿萨德';

// ---------------------------------------------------------------------------
// 主题
// ---------------------------------------------------------------------------

ThemeData buildAppTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: kFontFamily,
    fontFamilyFallback: kFontFallback,
    colorScheme: scheme.copyWith(
      primary: AppColors.primary,
      surface: AppColors.surface,
      error: AppColors.error,
    ),
    scaffoldBackgroundColor: AppColors.surface,

    // 这套 UI 是扁平的：去掉水波纹与点击高亮，否则 Material 默认观感会漏出来。
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,

    // 光标 / 选区。选区用 12% 主色，比 Material 默认的 40% 淡得多，
    // 压在灰底和白底输入框上都不刺眼。
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.primary,
      selectionColor: AppColors.primarySoft,
      selectionHandleColor: AppColors.primary,
    ),

    // 输入框的基础样式：边框由 LabeledField 自己画（它是两格紧贴的复合控件），
    // 这里只把 Material 默认的填充、边框、内边距全部清掉，避免出现「双层边框」。
    inputDecorationTheme: const InputDecorationTheme(
      filled: false,
      isDense: true,
      contentPadding: EdgeInsets.zero,
      hintStyle: TextStyle(
        fontSize: kFontHint,
        color: AppColors.textMuted,
        fontFamily: kFontFamily,
        fontFamilyFallback: kFontFallback,
      ),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
    ),

    // 表格里那些内容不可控的列会挂 Tooltip。默认的深色气泡太「Material」，
    // 换成白底细边框 + 12 号字，与整体控件语言一致。
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: WorkColors.fieldFill,
        border: Border.all(color: WorkColors.border, width: 1),
        borderRadius: BorderRadius.circular(kRadius),
      ),
      textStyle: const TextStyle(
        fontSize: kFontHint,
        color: WorkColors.textPrimary,
        fontFamily: kFontFamily,
        fontFamilyFallback: kFontFallback,
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: AppColors.primary,
      ),
    ),
  );
}
