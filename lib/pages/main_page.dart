// ---------------------------------------------------------------------------
// 工作台主页面：标题条 + 左栏三张卡片 + 右侧标签条与三张表
//
// 这一层是「页面骨架 + 状态持有者」：
//   · 所有 TextEditingController / 下拉选中值 / Tab 下标 / 每张表的选中行集合
//     都在这里创建与释放，子组件一律无状态、只画 + 转发回调；
//   · 业务动作（登录 / 发送 / 查询 / 加入修改）一律留空实现 —— 本任务是纯界面
//     还原，回调里没有任何网络、文件或 FFI 调用；
//   · 表格右键菜单的「全选 / 反选 / 删除选中 / 删除成功」操作的是本地占位数据，
//     属于界面行为，不是业务逻辑（没有请求、没有落盘）。
//
// 【列宽为什么不会被这里的 setState 冲掉】
// 三张表各自把列宽存在自己的 State 里（见 task_table.dart 的说明）。本页面每次
// 重建只重传 columns / rows / selected，表格内部的宽度状态不受影响 ——
// 拖好列宽之后点任意按钮、切任意 Tab，宽度都保持原样。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:pigeon_core/pigeon_core.dart';

import 'package:app_ui/models.dart';
import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/drawer_panels.dart';
import 'package:app_ui/widgets/flat_tab_bar.dart';
import 'package:app_ui/widgets/nav_bar.dart';
import 'package:app_ui/widgets/panel_controls.dart';
import 'package:app_ui/widgets/setting_table.dart';
import 'package:app_ui/widgets/task_table.dart';
import 'package:app_ui/widgets/work_snack.dart';
import 'package:app_ui/widgets/work_title_bar.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key, this.loginAccount, this.onLogout});

  /// 验证页登录成功后带过来的账号。
  ///
  /// 工作台的「登录区」自己也有账户输入框（.ui 的 lineEdit_zh），这里是把它
  /// **预填**上，而不是锁死 —— 用户仍然可以在工作台里换另一个号。
  final String? loginAccount;

  /// 「退出登录」时回到验证页。
  ///
  /// 为空表示没有验证页（单独跑工作台时），此时只清空本地输入，停留在原页。
  final VoidCallback? onLogout;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  // ---- 输入框控制器（本类持有 → 本类负责 dispose）----
  //
  // 【命名规则：与 .ui 的 objectName 一一对应】
  // 需求是「所有组件的 objectName 改为 ui 的 objectName」，所以这里的每个字段都
  // 直接取 config.ui / untitled.ui 里的控件名（去掉下划线、转小驼峰）：
  //   lineEdit_zh      → _lineEditZh        账户
  //   lineEdit_mm      → _lineEditMm        密码
  //   lineEdit_zfmm    → _lineEditZfmm      支付密码
  //   lineEdit_cpxx    → _lineEditCpxx      藏品信息
  //   lineEdit_cpid    → _lineEditCpid      藏品Id
  //   lineEdit_sl      → _lineEditSl        数量
  //   lineEdit_jg      → _lineEditJg        价格
  //   lineEdit_cpxx_2  → _lineEditCpxx2     信息区里那个 key 输入框
  //   lineEdit_bf      → _lineEditBf        并发
  //   lineEdit_shqz    → _lineEditShqz      上号器区前缀
  //   lineEdit_tz      → _lineEditTz        通知区地址
  // 这样从 Flutter 代码反查 .ui 不用再靠记忆猜名字。
  final TextEditingController _lineEditZh = TextEditingController();
  final TextEditingController _lineEditMm = TextEditingController();
  final TextEditingController _lineEditZfmm = TextEditingController();
  final TextEditingController _lineEditCpxx = TextEditingController();
  final TextEditingController _lineEditCpid = TextEditingController();
  // .ui 里这两个输入框的 text 分别是 "1" / "100"，原样作为默认值。
  final TextEditingController _lineEditSl = TextEditingController(text: '1');
  final TextEditingController _lineEditJg = TextEditingController(text: '100');

  /// 信息区里那个 placeholder 为 `key` 的输入框（.ui 的 lineEdit_cpxx_2）。
  ///
  /// 它在 .ui 里是 `enabled = false` 的：没有登录时没有可填的 key。这里按同样的
  /// 语义做成禁用态，登录成功后才由业务层打开（本任务不接业务，保持禁用）。
  final TextEditingController _lineEditCpxx2 = TextEditingController();

  /// 操作区的「并发」输入框（.ui 的 lineEdit_bf），默认值 "1"。
  final TextEditingController _lineEditBf = TextEditingController(text: '1');

  // ---- 下拉选中值 ----
  /// 信息区顶部那个 QComboBox 在 .ui 里没有 item，只有 currentText 为空。
  /// 保留成「空列表 + 提示」，等真正接上数据源时往里塞候选即可。
  String? _comboBoxXx;
  static const List<String> _comboBoxXxItems = <String>[];

  static const List<String> _comboBoxGnItems = <String>['默认模式', '一键下单'];
  static const List<String> _comboBoxFsItems = <String>[
    '锁单',
    '提取支付链接',
    '余额支付',
  ];
  static const List<String> _comboBoxZfItems = <String>[
    '易宝自动支付',
    '汇付自动支付',
    '连连自动支付',
    '衫德自动支付',
  ];

  /// 通知区的通知方式下拉（.ui 的 comboBox_tzxx，三项写死在 .ui 里）。
  static const List<String> _comboBoxTzxxItems = <String>[
    '息知',
    'wxpur',
    'baerk',
  ];

  /// 默认选中项取自 .ui 的 currentText，不能改成别的。
  String? _comboBoxGn = '默认模式';
  String? _comboBoxFs = '锁单';
  String? _comboBoxZf = '易宝自动支付';
  String? _comboBoxTzxx = '息知';

  /// 「运行中」开关。.ui 里没有这个状态位，但「操作」卡片上的「开始 / 结束」
  /// 两个按钮需要它来驱动：开始之后表格整表只读（TaskTable.enabled = false），
  /// 结束之后恢复可编辑。这一位纯粹是界面状态，不涉及任何业务调用。
  bool _running = false;

  // ---- 底部图标条与右侧抽屉 ----
  /// 当前抽屉对应哪一项；null = 抽屉关着。
  ///
  /// 用「哪一项」而不是「开 / 关 + 是哪一项」两个字段：抽屉必然同时有且只有一个
  /// 归属，拆成两个字段就一定会有「开着但不知道是哪一项」的中间态。
  NavDestination? _drawer;

  /// 设置页（抽屉里的「设置」）的状态。
  ///
  /// 逐项对应 config.ui 里的勾选框：
  ///   checkBox_qyxh   → _checkBoxQyxh    启用小号
  ///   checkBox_qyhk   → _checkBoxQyhk    启用滑块
  ///   checkBox_qydl   → _checkBoxQydl    启用代理
  ///   checkBox_qydl_2 → _checkBoxQydl2   通知区的「启用代理」
  /// 与左栏一样，这些都只是界面状态，不落盘、不接业务。
  bool _checkBoxQyxh = false;
  bool _checkBoxQyhk = false;
  bool _checkBoxQydl = false;
  bool _checkBoxQydl2 = false;

  /// 设置页里两个输入框。归页面持有 —— 抽屉每次开关都会重建内容，
  /// controller 若在 build 里现造，打字打到一半切走再切回来就丢了。
  ///
  /// 上号器区只剩「前缀」一个（lineEdit_shqz）：更早的 lineEdit_3（格式说明）
  /// 已被 .ui 删除，那段文字并入了分组标题。
  final TextEditingController _lineEditShqz = TextEditingController();

  /// 通知区（groupBox「通知区」）里的地址输入框（.ui 的 lineEdit_tz）。
  final TextEditingController _lineEditTz = TextEditingController();

  /// 小号表的数据。取自 config.ui 的 tableWidget_xh（列名 no / phone / token）。
  ///
  /// 预置 10 条模拟数据：表格高度锁定在 config.ui 的 141 附近，10 条放不下，
  /// 所以框内可滚动 —— 这样滚动条、隔行底色、表头固定这几件事都能一眼看到。
  List<SubAccount> _subAccounts = List<SubAccount>.of(kDemoSubAccounts);

  // ---- Tab 与三张表 ----
  static const List<String> _tabTitles = <String>['运行', '订单信息', '完成'];
  int _tabIndex = 0;

  /// 三张表各自的行与选中集合。
  ///
  /// 分成三份而不是共用一份：三张表的内容本来就不同（运行中的账号 / 已下单 /
  /// 已完成），选中集合也必须分开 —— 否则在「运行」里勾中的下标跑到「完成」里
  /// 会选中另一行。
  List<TaskRow> _runRows = List<TaskRow>.of(kDemoRunRows);
  List<TaskRow> _orderRows = List<TaskRow>.of(kDemoOrderRows);
  List<TaskRow> _doneRows = List<TaskRow>.of(kDemoDoneRows);

  final Set<int> _runSelected = <int>{};
  final Set<int> _orderSelected = <int>{};
  final Set<int> _doneSelected = <int>{};

  @override
  void initState() {
    super.initState();
    /* 设置页里输入框的当前值要回显到面板上。
     *
     * 【为什么必须手动监听】
     * TextField 打字只通知它自己的 EditableText，不会触发页面 setState ——
     * 所以 _buildDrawerBody() 不会重跑。这个监听让「抽屉开着时打字」能
     * 实时反映到面板上。
     *
     * 只在「抽屉正开着设置面板」时才 setState：抽屉没开时每次按键都重建整页
     * （含三张表）是纯粹的浪费。 */
    _lineEditShqz.addListener(_onSettingFieldChanged);
    _lineEditTz.addListener(_onSettingFieldChanged);
    // 个人中心的头像首字母与「已登录 / 未登录」也读 _lineEditZh.text，同一个坑。
    _lineEditZh.addListener(_onAccountChanged);

    /* 验证页登录成功带过来的账号，预填进「登录区」的账户输入框。
     *
     * 在 initState 里填而不是在 build 里：build 会被调用很多次（每次 setState
     * 都跑），在里面写 controller.text 会把用户后来的修改反复覆盖掉 ——
     * 表现是「在工作台里改了账号，一刷新又变回登录时那个」。
     *
     * 放在 addListener 之后：这样赋值本身也会触发 _onAccountChanged，
     * 个人中心面板如果正好开着能立刻显示新账号。 */
    final String? preset = widget.loginAccount;
    if (preset != null && preset.isNotEmpty) {
      _lineEditZh.text = preset;
    }

    /* 进入工作台 = 登录已成：开启登录心跳。
     *
     * 【心跳是干什么的】
     * C 侧起一个后台线程，每 10 分钟调一次 timeout.lg 保活（用的是登录 / 注册 /
     * 充值响应里带回来的会话串）。不发它，服务端会把这次登录判成掉线。
     *
     * 【为什么在这里开、不在登录页开】
     * 登录页只是「拿到了 Token」，用户可能马上关掉、也可能还要去注册页转一圈；
     * 只有真正进了工作台才算「在用」。放在 initState 里，配合 dispose 里的
     * pcHeartbeatStop，页面存活期就是心跳存活期，不会漏也不会残留。
     *
     * 【幂等】C 侧 pc_bsphp_heartbeat_start 已在跑时重复调用返回 PC_OK 且不叠加
     * 线程（见其实现），所以「退出登录再登录」这种来回切不会攒出多条心跳线程。
     *
     * 【为什么这里要自己写一行日志】
     * C 侧对「心跳成功」是**静默**的（见 pc_bsphp.c 的 hb_loop：PC_HB_OK 直接
     * 进下一轮，不写任何日志）—— 这是刻意的，否则每 10 分钟一条「一切正常」
     * 会把日志刷满。但那样一来，用户在日志里看不到「心跳到底起没起」。
     * 所以这里在**启动那一刻**补一条，把结论和返回码都记下来：
     *   rc=0  → 已启动（或复用已在跑的线程）
     *   rc!=0 → 起不来，原因看返回码（PC_ERR_SERVER = CreateThread/CreateEvent 失败）
     * 之后的心跳成败由 C 侧按需记录（只在暂时失败 / 授权失效时写）。
     *
     * 【返回值仍然不判】心跳起不来不该挡住用户用工作台 —— 记完日志继续。 */
    final int hbRc = pcHeartbeatStart();
    pcLog(hbRc == PcStatus.ok
        ? '[心跳] 已开启（每 10 分钟一次 timeout.lg 保活；成功时不写日志，'
            '只在失败 / 授权失效时记录）'
        : '[心跳] 启动失败 rc=$hbRc —— 服务端可能把本次登录判成掉线');
  }

  void _onSettingFieldChanged() {
    if (_drawer == NavDestination.settings && mounted) {
      setState(() {});
    }
  }

  void _onAccountChanged() {
    if (_drawer == NavDestination.profile && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    /* 离开工作台（退出登录 / 关窗）：停掉心跳线程。
     *
     * 协作式停止：置标志 + 唤醒等待中的线程，本调用立即返回，不等线程 join
     * （它可能正卡在一次最长 25s 的网络请求里）。需要确认真的收干净时用
     * pcHeartbeatIsRunning 轮询 —— 关闭窗口那条路径由 main.dart 的
     * onWindowClose 统一处理，那里不轮询是因为紧接着就 pcCoreShutdown 了。
     *
     * 放在最前面：后面那串 dispose 只是释放 Dart 侧对象，与心跳无关；
     * 先停线程可以尽早停止产生新的日志写入。
     *
     * 【日志写在 stop 之后】与 initState 里那条「已开启」成对，方便在运行日志里
     * 按时间对齐「什么时候进的工作台、什么时候退的」。注意 stop 是协作式的，
     * 这条日志只表示「已发出停止请求」，线程真正退出可能还要几百毫秒。 */
    pcHeartbeatStop();
    pcLog('[心跳] 已请求停止（离开工作台）');

    // 先摘监听再释放：dispose 期间 controller 还会发一次通知，
    // 那时如果回调还在，就会对已 unmount 的 State 调 setState。
    _lineEditShqz.removeListener(_onSettingFieldChanged);
    _lineEditTz.removeListener(_onSettingFieldChanged);
    _lineEditZh.removeListener(_onAccountChanged);
    _lineEditZh.dispose();
    _lineEditMm.dispose();
    _lineEditZfmm.dispose();
    _lineEditCpxx.dispose();
    _lineEditCpid.dispose();
    _lineEditSl.dispose();
    _lineEditJg.dispose();
    _lineEditCpxx2.dispose();
    _lineEditBf.dispose();
    _lineEditShqz.dispose();
    _lineEditTz.dispose();
    super.dispose();
  }

  void _snack(String message) => showWorkSnack(context, message);

  /// 「小号区」的「获取」按钮。
  ///
  /// 真实场景是去接口拉小号列表。这里没有网络层，所以只做一件有意义的事：
  /// 把列表按倒序重排（相当于「刷新了一遍」），让用户看得出按钮确实生效了。
  /// 接入真实数据源时，把这里换成 await 请求 + setState 即可。
  void _fetchSubAccounts() {
    setState(() {
      _subAccounts = _subAccounts.reversed.toList();
    });
    _snack('已刷新 ${_subAccounts.length} 个小号');
  }

  // -------------------------------------------------------------------------
  // 表格的选中 / 删除动作
  //
  // 只操作本页持有的三份行列表。真实接入时这些动作要改成调用数据源，
  // 但表格组件本身不用动 —— 它只负责把菜单项翻译成回调。
  // -------------------------------------------------------------------------

  /// 取某个 Tab 对应的行列表。
  ///
  /// 三个分支都写全（而不是 `_ =>` 兜底）：将来加第四个 Tab 时编译器会在这里
  /// 报错，不会静默落到「完成」表上。
  List<TaskRow> _rowsOf(int tabIndex) => switch (tabIndex) {
    0 => _runRows,
    1 => _orderRows,
    _ => _doneRows,
  };

  /// 取某个 Tab 对应的选中下标集合。
  Set<int> _selectedOf(int tabIndex) => switch (tabIndex) {
    0 => _runSelected,
    1 => _orderSelected,
    _ => _doneSelected,
  };

  /// 写入行集合并重新编号（**显示序号**从 1 连续），同时清掉越界的选中下标。
  ///
  /// 重新编号只改序号，状态 / 详情原样保留（由 copyWith 保证）—— 否则任何一次
  /// 删除都会把整张表的状态列打回默认值。
  void _setRows(int tabIndex, List<TaskRow> next) {
    final List<TaskRow> numbered = <TaskRow>[
      for (int i = 0; i < next.length; i++) next[i].copyWith(no: i + 1),
    ];
    setState(() {
      switch (tabIndex) {
        case 0:
          _runRows = numbered;
          _runSelected.removeWhere((int i) => i >= numbered.length);
        case 1:
          _orderRows = numbered;
          _orderSelected.removeWhere((int i) => i >= numbered.length);
        default:
          _doneRows = numbered;
          _doneSelected.removeWhere((int i) => i >= numbered.length);
      }
    });
  }

  void _toggleSelection(Set<int> selected, int index) {
    setState(() {
      if (selected.contains(index)) {
        selected.remove(index);
      } else {
        selected.add(index);
      }
    });
  }

  void _selectAll(int tabIndex) {
    final List<TaskRow> rows = _rowsOf(tabIndex);
    final Set<int> selected = _selectedOf(tabIndex);
    if (rows.isEmpty) {
      _snack('当前表格没有数据');
      return;
    }
    setState(() {
      selected
        ..clear()
        ..addAll(<int>[for (int i = 0; i < rows.length; i++) i]);
    });
    _snack('已全选 ${rows.length} 行');
  }

  void _invertSelection(int tabIndex) {
    final List<TaskRow> rows = _rowsOf(tabIndex);
    final Set<int> selected = _selectedOf(tabIndex);
    if (rows.isEmpty) {
      _snack('当前表格没有数据');
      return;
    }
    setState(() {
      final Set<int> next = <int>{
        for (int i = 0; i < rows.length; i++)
          if (!selected.contains(i)) i,
      };
      selected
        ..clear()
        ..addAll(next);
    });
    _snack('已反选，当前选中 ${selected.length} 行');
  }

  void _deleteSelected(int tabIndex) {
    final List<TaskRow> rows = _rowsOf(tabIndex);
    final Set<int> selected = _selectedOf(tabIndex);
    if (selected.isEmpty) {
      _snack('没有选中任何行');
      return;
    }
    final int removed = selected.length;
    final List<TaskRow> next = <TaskRow>[
      for (int i = 0; i < rows.length; i++)
        if (!selected.contains(i)) rows[i],
    ];
    setState(selected.clear);
    _setRows(tabIndex, next);
    _snack('已删除 $removed 行');
  }

  /// 「删除成功」：一次清掉所有状态为「成功」的行。
  ///
  /// 与「删除选中」分开成两项而不是合成一个带确认框的项，理由：两者选中的依据
  /// 完全不同 —— 前者靠用户勾选（下标集合），后者靠行的状态；混在一起用户没法
  /// 只删其中一类。这一项是「清理已完成的行」，跑完一轮之后最常用的动作。
  void _deleteSucceeded(int tabIndex) {
    final List<TaskRow> rows = _rowsOf(tabIndex);
    final List<TaskRow> next = <TaskRow>[
      for (final TaskRow r in rows)
        if (r.status != TaskStatus.succeeded) r,
    ];
    final int removed = rows.length - next.length;
    if (removed == 0) {
      _snack('没有状态为「成功」的行');
      return;
    }
    _selectedOf(tabIndex).clear();
    _setRows(tabIndex, next);
    _snack('已删除 $removed 行成功记录');
  }

  // -------------------------------------------------------------------------
  // 布局
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 没有 AppBar、没有原生菜单栏：标题条是自绘的 WorkTitleBar。
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const WorkTitleBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(kPanelPadding),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // 左栏固定 220：其中 8 留给滚动条，卡片可见宽仍是 212。
                  SizedBox(width: kPanelWidth, child: _buildLeftPanel()),
                  const SizedBox(width: kPanelPadding),
                  // 【为什么 Stack 只包右栏，不包整页】
                  // 抽屉与遮罩只覆盖右侧工作区，左栏必须保持可读可点 ——
                  // 用户常常边看设置边改左栏参数。把 Stack 提到整页外面
                  // （或用 Scaffold.endDrawer）会让遮罩连左栏一起压暗。
                  Expanded(
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(child: _buildRightSide()),
                        /* 遮罩与抽屉都常驻在树里，由各自的动画组件决定可见性。
                         *
                         * 早先是 `if (_drawer != null)` 条件插入：抽屉关闭时被
                         * 瞬间移除，滑入的柔和与消失的生硬形成对比，最容易被
                         * 感知成「卡了一下」。现在开关都走过渡（见 DrawerHost）。 */
                        Positioned.fill(
                          child: _DrawerScrim(
                            visible: _drawer != null,
                            onTap: _closeDrawer,
                          ),
                        ),
                        Positioned.fill(
                          child: DrawerHost(
                            current: _drawer,
                            onClose: _closeDrawer,
                            builder: _buildDrawerBody,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 左栏：四张卡片自上而下堆叠，底部一行图标条。
  ///
  /// 【为什么按可用高度逐档收紧间距】
  /// 左栏四张卡片（登录区 / 信息区 / 选项区 / 操作）在设计窗口 1048x682 下，
  /// 仅控件与按钮的硬高度就已经超过可用高度了 —— 能收的只有空白。所以这里量
  /// 真实可用高度，从宽到紧试三档（normal → compact → dense），取第一个装得下
  /// 的；三档都装不下才让它滚。
  ///
  /// 【图标条为什么不跟着卡片一起滚】
  /// 图标条是常驻入口，滚走就找不到了。所以它放在滚动容器**外面**：卡片区
  /// 自己滚，图标条钉在底部。选档时也要把图标条的高度从可用高度里扣掉。
  ///
  /// 仍然保留 SingleChildScrollView 兜底：万一某个系统的字体度量把
  /// [PanelMetrics.contentHeight] 算得偏小，宁可让它能滚，也绝不能溢出
  /// （溢出会直接画黄黑警示条）。
  Widget _buildLeftPanel() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final Widget navBar = Padding(
          padding: const EdgeInsets.only(top: kNavBarGap),
          child: NavBar(
            active: _drawer,
            onSelect: _onNavSelect,
          ),
        );

        // 无界高度（理论上不会出现，防御一下）：用常规档 + 图标条。
        if (!c.hasBoundedHeight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildLeftColumn(PanelMetrics.normal),
              navBar,
            ],
          );
        }

        // 图标条是常驻的，先把它占的高度扣掉，剩下的才是卡片区可用高度。
        final double cardsAvail =
            c.maxHeight - kNavBarGap - kNavButtonSize;

        // 从宽到紧，取第一个装得下的档位。
        PanelMetrics chosen = PanelMetrics.dense;
        for (final PanelMetrics candidate in PanelMetrics.byDescendingSpace) {
          if (candidate.contentHeight <= cardsAvail) {
            chosen = candidate;
            break;
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: _LeftPanelScroller(child: _buildLeftColumn(chosen)),
            ),
            navBar,
          ],
        );
      },
    );
  }

  /// 点底部图标：同一项再点一次 = 收起；点另一项 = 换成那一项。
  void _onNavSelect(NavDestination d) {
    setState(() => _drawer = _drawer == d ? null : d);
  }

  /// 收起抽屉。
  void _closeDrawer() => setState(() => _drawer = null);

  /// 按给定 destination 造出抽屉内容（不含外壳，外壳由 [DrawerHost] 负责）。
  ///
  /// 三个分支各自返回一块面板；文案与动作都在 widgets/drawer_panels.dart 里，
  /// 这里只负责把页面的状态接进去 —— 与左栏卡片的分工一致。
  ///
  /// 【为什么回显能实时更新】
  /// settings 分支读的是 _lineEditShqz/_lineEditTz.text、profile 分支读的是
  /// _lineEditZh.text，都在 initState 里挂了监听（见 _onSettingFieldChanged /
  /// _onAccountChanged），打字时会 setState 让这里重跑。
  Widget _buildDrawerBody(NavDestination d) {
    return switch (d) {
      NavDestination.settings => SettingsPanel(
        checkBoxQyxh: _checkBoxQyxh,
        checkBoxQyhk: _checkBoxQyhk,
        checkBoxQydl: _checkBoxQydl,
        checkBoxQydl2: _checkBoxQydl2,
        lineEditShqzController: _lineEditShqz,
        lineEditTzController: _lineEditTz,
        comboBoxTzxx: _comboBoxTzxx,
        comboBoxTzxxItems: _comboBoxTzxxItems,
        subAccounts: _subAccounts,
        onCheckBoxQyxhChanged: (bool v) =>
            setState(() => _checkBoxQyxh = v),
        onCheckBoxQyhkChanged: (bool v) =>
            setState(() => _checkBoxQyhk = v),
        onCheckBoxQydlChanged: (bool v) =>
            setState(() => _checkBoxQydl = v),
        onCheckBoxQydl2Changed: (bool v) =>
            setState(() => _checkBoxQydl2 = v),
        onLineEditShqzChanged: (String v) => setState(() {}),
        onLineEditTzChanged: (String v) => setState(() {}),
        onComboBoxTzxxChanged: (String? v) =>
            setState(() => _comboBoxTzxx = v),
        onFetchSubAccounts: _fetchSubAccounts,
        onLinkSlider: () => _snack('滑块链接（待接入）'),
        onLinkLoader: () => _snack('上号器链接（待接入）'),
        onDisconnectLoader: () => _snack('上号器断开（待接入）'),
        onLinkProxy: () => _snack('代理链接（待接入）'),
        onTestNotify: () => _snack('通知测试（待接入）'),
      ),
      NavDestination.profile => ProfilePanel(
        account: _lineEditZh.text,
        onLogout: _logout,
      ),
      NavDestination.menu => MenuPanel(
        onOpenDocs: () => _snack('使用说明（待接入）'),
        onOpenLogs: () => _snack('运行日志（待接入）'),
        onCheckUpdate: () => _snack('已是最新版本'),
        onAbout: () => _snack('$kWindowTitle · 界面还原工程'),
      ),
    };
  }

  /// 「退出登录」：清掉账号与密码，回到未登录态。
  ///
  /// 有验证页时（[MainPage.onLogout] 非空）交回上层切回登录页 —— 否则只是
  /// 清空了输入框，用户还停在工作台里，看起来像「退出没生效」。
  void _logout() {
    setState(() {
      _lineEditZh.clear();
      _lineEditMm.clear();
      _lineEditZfmm.clear();
      _drawer = null;
    });
    final VoidCallback? back = widget.onLogout;
    if (back != null) {
      back();
      return;
    }
    _snack('已退出登录');
  }

  /// 按给定档位堆出左栏的纵向列。
  Widget _buildLeftColumn(PanelMetrics m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _buildLoginCard(m),
        SizedBox(height: m.cardGap),
        _buildInfoCard(m),
        SizedBox(height: m.cardGap),
        _buildOptionCard(m),
        SizedBox(height: m.cardGap),
        _buildActionCard(m),
      ],
    );
  }

  /// ① 登录区（`groupBox_login`）
  Widget _buildLoginCard(PanelMetrics m) {
    return PanelGroupBox(
      objectName: kGroupBoxLogin,
      title: '登录区',
      padding: m.groupBoxPadding,
      sectionGap: m.sectionGap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          LabeledField(
            key: const ValueKey<String>(kLineEditZh),
            label: '账户',
            controller: _lineEditZh,
            hint: '请输入账号',
          ),
          SizedBox(height: m.rowGap),
          LabeledField(
            key: const ValueKey<String>(kLineEditMm),
            label: '密码',
            controller: _lineEditMm,
            hint: '请输入密码',
            obscure: true,
          ),
          SizedBox(height: m.rowGap),
          // 「支付密码」标签 4 个字，标签格给 51 正好放得下。
          LabeledField(
            key: const ValueKey<String>(kLineEditZfmm),
            label: '支付密码',
            controller: _lineEditZfmm,
            hint: '支付密码',
            obscure: true,
          ),
          SizedBox(height: m.preButtonGap),
          // .ui 里两个按钮是 75 宽 + 25 间距，落在 181 宽的内容区里；
          // 这里改成等宽两格，宽度随面板自适应，视觉比例一致。
          Row(
            children: <Widget>[
              Expanded(
                child: PanelButton(
                  key: const ValueKey<String>(kPushButtonFs),
                  label: '发送',
                  height: kCompactButtonHeight,
                  // .ui 里 pushButton_fs 的 enabled = false：未登录时没有可发的
                  // 东西。禁用态用 onPressed: null 表达。
                  onPressed: null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PanelButton(
                  key: const ValueKey<String>(kPushButtonDl),
                  label: '登录',
                  primary: true,
                  height: kCompactButtonHeight,
                  // 业务动作留空实现：本任务只做界面。
                  onPressed: () {},
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// ② 信息区（`groupBox_xx`）
  Widget _buildInfoCard(PanelMetrics m) {
    return PanelGroupBox(
      objectName: kGroupBoxXx,
      title: '信息区',
      padding: m.groupBoxPadding,
      sectionGap: m.sectionGap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 顶部：下拉占满一行，右侧 41x21 的「查询」小按钮。
          // .ui 里下拉是 151 宽 + 按钮 41 宽（x=160），这里改成 Expanded + 固定宽，
          // 面板变宽时只有下拉变宽，按钮尺寸不变。
          Row(
            children: <Widget>[
              Expanded(
                child: PanelDropdown(
                  key: const ValueKey<String>(kComboBoxXx),
                  value: _comboBoxXx,
                  items: _comboBoxXxItems,
                  hint: '选择已保存账号',
                  onChanged: (String? v) => setState(() => _comboBoxXx = v),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: kSmallButtonWidth,
                height: kSmallButtonHeight,
                child: PanelButton(
                  key: const ValueKey<String>(kPushButtonCx),
                  label: '查询',
                  height: kSmallButtonHeight,
                  onPressed: () {},
                ),
              ),
            ],
          ),
          SizedBox(height: m.rowGap),
          // .ui 的 lineEdit_cpxx_2：整行 181 宽、placeholder 为 "key"、
          // alignment = AlignCenter、enabled = false。
          //
          // 【为什么做成整行无标签的输入框】
          // 它没有配对的 QLabel（其余六行都是「标签格 + 输入格」），而是自己占
          // 满整行 181 —— 从名字看是「藏品信息 2」，从位置看紧跟在账号下拉下面，
          // 是下拉选中之后回填的只读值。这里照 .ui 的形状还原：无标签、居中、
          // 禁用态，而不是硬塞进 LabeledField 的两格结构。
          SizedBox(
            height: kRowHeight,
            child: BareField(
              key: const ValueKey<String>(kLineEditCpxx2),
              controller: _lineEditCpxx2,
              hint: 'key',
              enabled: false,
            ),
          ),
          SizedBox(height: m.rowGap),
          LabeledField(
            key: const ValueKey<String>(kLineEditCpxx),
            label: '藏品信息',
            controller: _lineEditCpxx,
            hint: '自己填写或选择',
          ),
          SizedBox(height: m.rowGap),
          LabeledField(
            key: const ValueKey<String>(kLineEditCpid),
            label: '藏品Id',
            controller: _lineEditCpid,
            hint: '自己填写或选择',
          ),
          SizedBox(height: m.rowGap),
          LabeledField(
            key: const ValueKey<String>(kLineEditSl),
            label: '数量',
            controller: _lineEditSl,
            keyboardType: TextInputType.number,
          ),
          SizedBox(height: m.rowGap),
          LabeledField(
            key: const ValueKey<String>(kLineEditJg),
            label: '价格',
            controller: _lineEditJg,
            keyboardType: TextInputType.number,
          ),
          SizedBox(height: m.preButtonGap),
          // .ui 里是 181x23 的整行按钮，这里用 23 高 + 占满宽。
          PanelButton(
            key: const ValueKey<String>(kPushButtonJr),
            label: '加入修改',
            height: kCompactButtonHeight,
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  /// ③ 选项区（`groupBox_xxq`）：三行「标签 + 下拉」。
  Widget _buildOptionCard(PanelMetrics m) {
    return PanelGroupBox(
      objectName: kGroupBoxXxq,
      title: '选项区',
      padding: m.groupBoxPadding,
      sectionGap: m.sectionGap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _LabeledDropdown(
            dropdownObjectName: kComboBoxGn,
            label: '功能',
            value: _comboBoxGn,
            items: _comboBoxGnItems,
            onChanged: (String? v) => setState(() => _comboBoxGn = v),
          ),
          SizedBox(height: m.rowGap),
          _LabeledDropdown(
            dropdownObjectName: kComboBoxFs,
            label: '方式',
            value: _comboBoxFs,
            items: _comboBoxFsItems,
            onChanged: (String? v) => setState(() => _comboBoxFs = v),
          ),
          SizedBox(height: m.rowGap),
          _LabeledDropdown(
            dropdownObjectName: kComboBoxZf,
            label: '支付',
            value: _comboBoxZf,
            items: _comboBoxZfItems,
            onChanged: (String? v) => setState(() => _comboBoxZf = v),
          ),
        ],
      ),
    );
  }

  /// ④ 操作区（`groupBox`）：并发输入框 + 「开始 / 结束」。
  ///
  /// 对应 .ui 里的 groupBox（y=480，211x81），标题「操作」。控件布局与「登录区」
  /// 同构：上面一行「标签格 + 输入格」，下面一行两个等宽按钮。
  ///
  /// 【开始 / 结束 的禁用互斥】
  /// 两个按钮不可能同时可用 —— 没在跑的时候「开始」可点、「结束」不可点，反之
  /// 亦然。用 onPressed: null 表达禁用（与「发送」一致），不另加 enabled 参数。
  Widget _buildActionCard(PanelMetrics m) {
    return PanelGroupBox(
      objectName: kGroupBox,
      title: '操作',
      padding: m.groupBoxPadding,
      sectionGap: m.sectionGap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          LabeledField(
            key: const ValueKey<String>(kLineEditBf),
            label: '并发',
            controller: _lineEditBf,
            keyboardType: TextInputType.number,
          ),
          SizedBox(height: m.preButtonGap),
          // .ui 里两个按钮是 75 宽、左 20 / 右 120（间距 25），落在 181 宽的内容区；
          // 与登录区一样改成等宽两格，宽度随面板自适应。
          Row(
            children: <Widget>[
              Expanded(
                child: PanelButton(
                  key: const ValueKey<String>(kPushButtonKs),
                  label: '开始',
                  primary: true,
                  height: kCompactButtonHeight,
                  onPressed: _running ? null : _startRun,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PanelButton(
                  key: const ValueKey<String>(kPushButtonJs),
                  label: '结束',
                  height: kCompactButtonHeight,
                  onPressed: _running ? _stopRun : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 「开始」：把整表切成只读，并给一条提示。
  ///
  /// 只改界面状态（[_running]），不启动任何后台任务 —— 本任务仍是纯界面还原。
  void _startRun() {
    setState(() => _running = true);
    _snack('已开始，运行期间表格不可修改');
  }

  /// 「结束」：恢复表格可编辑。
  void _stopRun() {
    setState(() => _running = false);
    _snack('已结束');
  }

  /// 右侧：标签条 + 三张表（`tabWidget_gongzuoqu`）。
  ///
  /// 用 IndexedStack 而不是每次重建当前表：三张表各自持有列宽与滚动位置，
  /// 换 Tab 时若销毁重建，用户拖好的列宽会全部回到默认比例。
  Widget _buildRightSide() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FlatTabBar(
          key: const ValueKey<String>(kTabWidgetGongzuoqu),
          tabs: _tabTitles,
          index: _tabIndex,
          onChanged: (int i) => setState(() => _tabIndex = i),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: IndexedStack(
            index: _tabIndex,
            children: <Widget>[
              _buildTable(
                kTableWidgetYx,
                0,
                kRunColumns,
                _runRows,
                _runSelected,
                '暂无运行中的任务',
              ),
              _buildTable(
                kTableWidgetDdxx,
                1,
                kOrderColumns,
                _orderRows,
                _orderSelected,
                '暂无订单信息',
              ),
              _buildTable(
                kTableWidgetWc,
                2,
                kDoneColumns,
                _doneRows,
                _doneSelected,
                '暂无已完成的任务',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTable(
    String objectName,
    int tabIndex,
    List<TaskColumn> columns,
    List<TaskRow> rows,
    Set<int> selected,
    String emptyHint,
  ) {
    return TaskTable(
      key: ValueKey<String>(objectName),
      columns: columns,
      rows: rows,
      selected: selected,
      emptyHint: emptyHint,
      onToggleSelection: (int i) => _toggleSelection(selected, i),
      onSelectAll: () => _selectAll(tabIndex),
      onInvertSelection: () => _invertSelection(tabIndex),
      onDeleteSelected: () => _deleteSelected(tabIndex),
      onDeleteSucceeded: () => _deleteSucceeded(tabIndex),
      // 「操作」卡片的「开始 / 结束」驱动整表只读（见 _buildActionCard）。
      // 禁用态的提示通道一直就是接好的，这里只是把开关接上。
      enabled: !_running,
      onDisabledTap: _snack,
    );
  }
}

// ---------------------------------------------------------------------------
// 页面私有：抽屉遮罩
// ---------------------------------------------------------------------------

/// 抽屉打开时压在右侧工作区上的半透明遮罩，自带淡入淡出。
///
/// 【为什么常驻在树里而不是条件插入】
/// 条件插入会让遮罩「啪」地出现 / 消失。抽屉本体是 300ms 滑入的，遮罩瞬间
/// 到位就会显得两者不同步。这里用 AnimatedOpacity 跟着抽屉一起渐变：
/// 进场与 [kDrawerDuration] 同长，退场用更短的 [kDrawerExitDuration]。
///
/// 【浓度来自 theme】
/// 早先这里直接写死 `Color(0x2E000000)`，而 theme.dart 里另有一个
/// `kDrawerScrimAlpha = 0.18` 没人用 —— 注释声称取的是那个常量，实际是硬编码。
/// 那种「文档与代码背离」比单纯硬编码更难查：改常量毫无效果，但注释说已生效。
class _DrawerScrim extends StatelessWidget {
  const _DrawerScrim({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // 收起后不吃点击，否则遮罩会挡住表格的右键菜单。
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: visible ? kDrawerDuration : kDrawerExitDuration,
        curve: visible ? kSlideInCurve : kSlideOutCurve,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ColoredBox(
            color: Colors.black.withValues(alpha: kDrawerScrimAlpha),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 页面私有：左栏滚动容器
// ---------------------------------------------------------------------------

/// 左栏在窗口变矮时的滚动容器，自带独立控制器。
///
/// 单独成组件（而不是在 build 里现造 ScrollController）的原因与表格那边一样：
/// controller 实例必须跨帧稳定，否则每帧都换一个新实例，滚动位置会被重置。
///
/// 【滚动条只在真的需要时才出现】
/// 早先 `thumbVisibility: true` 是硬开：1048x682 下左栏其实完全放得下
/// （实测 maxScrollExtent = 0），却常驻一根灰条，还把卡片挤窄 8px。
/// 现在监听滚动位置，只有 maxScrollExtent > 0 才让出那条 8px 并显示滚动条 ——
/// 不需要滚动时卡片用满整个宽度，左右内边距也就对称了。
class _LeftPanelScroller extends StatefulWidget {
  const _LeftPanelScroller({required this.child});

  final Widget child;

  @override
  State<_LeftPanelScroller> createState() => _LeftPanelScrollerState();
}

class _LeftPanelScrollerState extends State<_LeftPanelScroller> {
  final ScrollController _controller = ScrollController();

  /// 当前是否真的需要滚动。决定滚动条可见性与右侧让位。
  bool _scrollable = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncScrollable);
  }

  /// 布局完成后才知道内容有多高，所以要在帧末同步一次。
  void _syncScrollable() {
    if (!_controller.hasClients) {
      return;
    }
    final bool next = _controller.position.maxScrollExtent > 0.5;
    if (next != _scrollable && mounted) {
      setState(() => _scrollable = next);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_syncScrollable);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 每帧结束后核对一次：内容高度变化（窗口缩放、字体度量差异）时
    // 不会触发滚动事件，只靠监听会漏掉。
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncScrollable());

    return Scrollbar(
      controller: _controller,
      // 需要滚动才显示；不需要时彻底不占位。
      thumbVisibility: _scrollable,
      thickness: kScrollThickness,
      radius: const Radius.circular(kScrollRadius),
      child: SingleChildScrollView(
        controller: _controller,
        // 只在需要滚动时留出滚动条的 8px，否则卡片可以用满整个宽度。
        padding: EdgeInsets.only(
          right: _scrollable ? kLeftPanelScrollGutter : 0,
        ),
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 页面私有：无标签的整行输入框
// ---------------------------------------------------------------------------
//
// 早先这里是私有类 `_BareField`。设置页的通知区（lineEdit_tz）也需要「没有标签、
// 自己占一格」的输入框，私有类跨不了文件 —— 已提到
// widgets/panel/bare_field.dart 成为公共的 BareField，两处共用。

// ---------------------------------------------------------------------------
// 页面私有：「标签 + 下拉」一行
// ---------------------------------------------------------------------------

/// 「功能 / 方式 / 支付」三行是「标签格 + 下拉格」的组合，与 LabeledField
/// 同一套两格语言，只是右格换成了 PanelDropdown。
///
/// 为什么不把 LabeledField 泛化成一个「右格可以塞任意控件」的组件：那样它就要
/// 多一个 child 参数、内部再判断「给的是 TextField 还是别的」，聚焦发光、禁用
/// 底色这些逻辑都要分叉。这里另写 20 行组合，两边各自单纯。
class _LabeledDropdown extends StatelessWidget {
  const _LabeledDropdown({
    required this.dropdownObjectName,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  /// 下拉在 .ui 里的 objectName（`comboBox_gn` / `comboBox_fs` / `comboBox_zf`）。
  final String dropdownObjectName;

  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kRowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            // 与 LabeledField 共用同一个标签格宽度，三张卡片的输入框左边界
            // 才落在同一条竖线上。
            width: kLabelWidth,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: WorkColors.panel,
              border: Border.all(color: WorkColors.border, width: 1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(kRadius),
                bottomLeft: Radius.circular(kRadius),
              ),
            ),
            child: Padding(
              // 与 LabeledField 的标签格同样的处理：51 宽的格子里放四字标签，
              // 任何水平内边距都会挤成省略号。
              padding: EdgeInsets.zero,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: kFontBody,
                    color: WorkColors.textPrimary,
                    fontFamily: kFontFamily,
                    fontFamilyFallback: kFontFallback,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: PanelDropdown(
              key: ValueKey<String>(dropdownObjectName),
              value: value,
              items: items,
              onChanged: onChanged,
              // 只圆右侧两角：左格（标签）只圆左边两角，中间共用 1px 边框，
              // 与 LabeledField 的两格语言一致。
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(kRadius),
                bottomRight: Radius.circular(kRadius),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
