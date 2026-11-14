// ---------------------------------------------------------------------------
// 界面模型：列定义、行数据、状态枚举
//
// 只描述「界面怎么显示」，不含任何业务逻辑 —— 没有网络、没有存储、没有调度。
// 三个表格（运行 / 订单信息 / 完成）用同一套 TaskRow，靠列定义 List<TaskColumn>
// 区分：同一行数据在不同表里显示的列不同（例如「完成」表多一列支付链接）。
//
// 【为什么列定义带 field 枚举而不是按下标取单元格】
// 早先的写法是 `cells[5]`、`cells[6]` 这种下标魔法，一旦某张表少一列（「运行」表
// 没有 Oid），所有下标就得跟着改，改漏一处就会把「状态」画到「Oid」格子里，
// 而且不会报错。带枚举之后，列与值的关系是编译期检查的。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';

/// 一列能显示什么。与 [TaskRow] 的取值方法一一对应。
enum TaskField {
  no('no'),
  phone('phone'),
  paypwd('paypwd'),
  token('token'),
  collection('藏品信息'),
  quantity('数量'),
  price('价格'),
  oid('Oid'),
  payLink('支付链接'),
  status('状态'),
  detail('任务详情');

  const TaskField(this.title);

  /// 表头文案。取自 .ui 的 `<column><property name="text">`，原样保留。
  final String title;
}

/// 任务状态。文案固定，不掺服务端内容 —— 服务端原话走「任务详情」列。
enum TaskStatus {
  running('运行中', WorkColors.running),
  waiting('等待', WorkColors.idle),
  succeeded('成功', WorkColors.brand),
  stopped('已结束', WorkColors.textHint),
  failed('失败', WorkColors.error),
  hasOrder('有订单', WorkColors.warning);

  const TaskStatus(this.label, this.color);

  final String label;

  /// 状态列圆点与文字的颜色。放在枚举上而不是 switch 里：新增状态时编译器
  /// 会逼着你在这里给出颜色，不会漏掉一支导致某一格画成默认黑。
  final Color color;
}

/// 表格列定义。
class TaskColumn {
  const TaskColumn({
    required this.field,
    required this.flex,
    required this.minWidth,
    this.tooltip = false,
  });

  final TaskField field;

  /// 表头文案（= field.title，留一个 getter 是为了调用处读起来像列属性）。
  String get title => field.title;

  /// 默认相对宽度。用户拖过分隔条之后实际宽度以表格 State 里的值为准。
  final int flex;

  /// 拖动时这一列能被压到的最小像素宽。
  ///
  /// 不能只靠「不小于 0」兜底：序号列被拖到 0 宽后整列消失，用户再也找不到
  /// 那条分隔线把它拖回来。给一个最小值，任何时候都留得下抓手。
  final double minWidth;

  /// 内容长度不可控的列（藏品信息 / Oid / 支付链接 / 任务详情）：
  /// 除省略号外再挂一层 Tooltip，鼠标停一下能看到全文。
  final bool tooltip;
}

// ---------------------------------------------------------------------------
// 三张表的列定义
//
// flex 权重来自需求：序号 9、phone 14、paypwd 13、token 13、藏品信息 12、
// 数量 / Oid / 支付链接 11、状态 13、任务详情 16。三张表各自归一化，所以
// 「运行」表（9 列，总 112）与「订单信息」表（8 列，总 101）虽然总权重不同，
// 都会把自己的可用宽度铺满。
//
// minWidth 取 44~66：序号只放数字，44 够；「藏品信息」是四字中文表头，
// 12.5 号字约 50px，加上左右各 6px 内边距需要 62 —— 给 66 才不会被省略号切掉。
// phone / token / 支付链接 / 任务详情 是英数混排，要能看出被截断的开头，给 60。
// ---------------------------------------------------------------------------

/// 「运行」表：no / phone / paypwd / token / 藏品信息 / 数量 / 价格 / 状态 / 任务详情。
const List<TaskColumn> kRunColumns = <TaskColumn>[
  TaskColumn(field: TaskField.no, flex: 9, minWidth: 44),
  TaskColumn(field: TaskField.phone, flex: 14, minWidth: 60),
  TaskColumn(field: TaskField.paypwd, flex: 13, minWidth: 52),
  TaskColumn(field: TaskField.token, flex: 13, minWidth: 60),
  TaskColumn(field: TaskField.collection, flex: 12, minWidth: 66, tooltip: true),
  TaskColumn(field: TaskField.quantity, flex: 11, minWidth: 44),
  // 「价格」与「数量」同权重：两者都是短数字，视觉上等宽最整齐。
  TaskColumn(field: TaskField.price, flex: 11, minWidth: 44),
  TaskColumn(field: TaskField.status, flex: 13, minWidth: 56),
  TaskColumn(field: TaskField.detail, flex: 16, minWidth: 60, tooltip: true),
];

/// 「订单信息」表：把「数量 / 价格」换成 Oid。
const List<TaskColumn> kOrderColumns = <TaskColumn>[
  TaskColumn(field: TaskField.no, flex: 9, minWidth: 44),
  TaskColumn(field: TaskField.phone, flex: 14, minWidth: 60),
  TaskColumn(field: TaskField.paypwd, flex: 13, minWidth: 52),
  TaskColumn(field: TaskField.token, flex: 13, minWidth: 60),
  TaskColumn(field: TaskField.collection, flex: 12, minWidth: 66, tooltip: true),
  TaskColumn(field: TaskField.oid, flex: 11, minWidth: 50, tooltip: true),
  TaskColumn(field: TaskField.status, flex: 13, minWidth: 56),
  TaskColumn(field: TaskField.detail, flex: 16, minWidth: 60, tooltip: true),
];

/// 「完成」表：在「订单信息」基础上再加一列支付链接。
const List<TaskColumn> kDoneColumns = <TaskColumn>[
  TaskColumn(field: TaskField.no, flex: 9, minWidth: 44),
  TaskColumn(field: TaskField.phone, flex: 14, minWidth: 60),
  TaskColumn(field: TaskField.paypwd, flex: 13, minWidth: 52),
  TaskColumn(field: TaskField.token, flex: 13, minWidth: 60),
  TaskColumn(field: TaskField.collection, flex: 12, minWidth: 66, tooltip: true),
  TaskColumn(field: TaskField.oid, flex: 11, minWidth: 50, tooltip: true),
  TaskColumn(field: TaskField.payLink, flex: 11, minWidth: 60, tooltip: true),
  TaskColumn(field: TaskField.status, flex: 13, minWidth: 56),
  TaskColumn(field: TaskField.detail, flex: 16, minWidth: 60, tooltip: true),
];

/// 一行任务记录（界面模型）。
class TaskRow {
  const TaskRow({
    required this.no,
    required this.phone,
    required this.paypwd,
    required this.token,
    required this.collection,
    required this.quantity,
    required this.price,
    required this.oid,
    required this.payLink,
    required this.status,
    required this.detail,
  });

  final int no;
  final String phone;
  final String paypwd;

  /// 会话凭据。表格里显示的是掩码（见 [displayToken]），完整值不进 UI。
  final String token;

  final String collection;
  final String quantity;
  final String price;
  final String oid;
  final String payLink;
  final TaskStatus status;
  final String detail;

  /// 按列取这一格的文本。
  ///
  /// 「状态」列返回 [TaskStatus.label]（固定文案），其余列返回原始字符串。
  /// 用 switch 穷举而不是下标：列定义增删时这里会编译报错，不会静默错位。
  String value(TaskField field) => switch (field) {
    TaskField.no => '$no',
    TaskField.phone => phone,
    TaskField.paypwd => paypwd,
    TaskField.token => displayToken,
    TaskField.collection => collection,
    TaskField.quantity => quantity,
    TaskField.price => price,
    TaskField.oid => oid,
    TaskField.payLink => payLink,
    TaskField.status => status.label,
    TaskField.detail => detail,
  };

  /// token 列的展示文本：只显示前 6 位 + 掩码。
  ///
  /// token 是账号会话凭据，整串渲染在界面上等同于泄露 —— 截图 / 录屏 / 远程
  /// 协助会把它整条带走。需要完整值时用 [token]（构建请求时读的就是它）。
  String get displayToken {
    if (token.isEmpty) {
      return '';
    }
    return token.length <= 6 ? ('*' * token.length) : '${token.substring(0, 6)}****';
  }

  /// 换一个状态 / 详情 / 序号。
  ///
  /// [no] 单独给出来是因为「删掉中间一行之后要重新编号」—— 表格的 no 列是从 1
  /// 连续编号的**显示序号**，与任何外部 id 无关。重新编号时状态与详情必须原样
  /// 保留（未给出的字段沿用），否则删一行就会把整张表的状态列打回默认值。
  TaskRow copyWith({int? no, TaskStatus? status, String? detail}) => TaskRow(
    no: no ?? this.no,
    phone: phone,
    paypwd: paypwd,
    token: token,
    collection: collection,
    quantity: quantity,
    price: price,
    oid: oid,
    payLink: payLink,
    status: status ?? this.status,
    detail: detail ?? this.detail,
  );
}

// ---------------------------------------------------------------------------
// 占位数据
//
// 本任务是纯界面还原，不接任何数据源。但空表看不出「表头与数据行列边界是否
// 逐像素对齐」「斑马纹 / 悬停 / 选中三态是否正常」，所以给三张表各配几条静态
// 样例行 —— 它们不来自网络、不可编辑业务含义，只是把界面撑起来看效果。
//
// 接入真实数据时：把这三组常量换成数据源即可，表格组件本身不用改。
// ---------------------------------------------------------------------------

const List<TaskRow> kDemoRunRows = <TaskRow>[
  TaskRow(
    no: 1,
    phone: '13800138000',
    paypwd: '******',
    token: 'tk_9f2c1a8b7d',
    collection: '龙年纪念章 · 首发',
    quantity: '1',
    price: '100',
    oid: '',
    payLink: '',
    status: TaskStatus.running,
    detail: '正在刷单，等待放单',
  ),
  TaskRow(
    no: 2,
    phone: '13900139001',
    paypwd: '******',
    token: 'tk_4b7e0d5c2f',
    collection: '龙年纪念章 · 首发',
    quantity: '2',
    price: '100',
    oid: '',
    payLink: '',
    status: TaskStatus.waiting,
    detail: '排队中',
  ),
  TaskRow(
    no: 3,
    phone: '13700137002',
    paypwd: '******',
    token: 'tk_1c3a9e6f40',
    collection: '龙年纪念章 · 首发',
    quantity: '1',
    price: '120',
    oid: '',
    payLink: '',
    status: TaskStatus.hasOrder,
    detail: '已有待装车运单，只刷单',
  ),
  TaskRow(
    no: 4,
    phone: '13600136003',
    paypwd: '******',
    token: 'tk_7d2b5a1e93',
    collection: '龙年纪念章 · 首发',
    quantity: '1',
    price: '100',
    oid: '',
    payLink: '',
    status: TaskStatus.failed,
    detail: '库存不足',
  ),
];

const List<TaskRow> kDemoOrderRows = <TaskRow>[
  TaskRow(
    no: 1,
    phone: '13800138000',
    paypwd: '******',
    token: 'tk_9f2c1a8b7d',
    collection: '龙年纪念章 · 首发',
    quantity: '1',
    price: '100',
    oid: '2026111400001234567',
    payLink: '',
    status: TaskStatus.succeeded,
    detail: '下单成功，等待支付',
  ),
  TaskRow(
    no: 2,
    phone: '13900139001',
    paypwd: '******',
    token: 'tk_4b7e0d5c2f',
    collection: '龙年纪念章 · 首发',
    quantity: '1',
    price: '100',
    oid: '2026111400001234568',
    payLink: '',
    status: TaskStatus.hasOrder,
    detail: '已有待装车运单',
  ),
  TaskRow(
    no: 3,
    phone: '13500135004',
    paypwd: '******',
    token: 'tk_5e8c3d0b61',
    collection: '龙年纪念章 · 首发',
    quantity: '1',
    price: '100',
    oid: '',
    payLink: '',
    status: TaskStatus.waiting,
    detail: '排队中',
  ),
];

const List<TaskRow> kDemoDoneRows = <TaskRow>[
  TaskRow(
    no: 1,
    phone: '13800138000',
    paypwd: '******',
    token: 'tk_9f2c1a8b7d',
    collection: '龙年纪念章 · 首发',
    quantity: '1',
    price: '100',
    oid: '2026111400001234567',
    payLink: 'https://pay.example.com/h5/pay?id=2026111400001234567',
    status: TaskStatus.succeeded,
    detail: '已提取支付链接',
  ),
  TaskRow(
    no: 2,
    phone: '13900139001',
    paypwd: '******',
    token: 'tk_4b7e0d5c2f',
    collection: '龙年纪念章 · 首发',
    quantity: '1',
    price: '100',
    oid: '2026111400001234568',
    payLink: 'https://pay.example.com/h5/pay?id=2026111400001234568',
    status: TaskStatus.succeeded,
    detail: '已提取支付链接',
  ),
  TaskRow(
    no: 3,
    phone: '13700137002',
    paypwd: '******',
    token: 'tk_1c3a9e6f40',
    collection: '龙年纪念章 · 首发',
    quantity: '1',
    price: '120',
    oid: '',
    payLink: '',
    status: TaskStatus.stopped,
    detail: '已结束（无订单）',
  ),
];
