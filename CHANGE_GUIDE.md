# 改动指南：控件 / UI / 数据 / 测试

> 这份文档取代 `UI_GUIDE.md`（那份的行号已全部过期，且仍在讲已删除的
> `CheckBoxRow`、单一 `kDrawerWidth`）。本文档的锚点全部是**可搜索的内容**
> 而非行号 —— 行号每次改动都会漂移，内容不会。

## 目录

- [0. 三分钟上手](#0-三分钟上手)
- [1. 工程地图](#1-工程地图)
- [2. 五条铁律](#2-五条铁律)
- [3. objectName：Flutter 与 .ui 的唯一契约](#3-objectnameflutter-与-ui-的唯一契约)
- [4. 改文案：全部锚点表](#4-改文案全部锚点表)
- [5. 改控件：常用组件的完整参数](#5-改控件常用组件的完整参数)
- [6. 加控件：四个可照抄的配方](#6-加控件四个可照抄的配方)
- [7. 改布局：三种排布范式](#7-改布局三种排布范式)
- [8. 改颜色与尺寸：theme.dart 全表](#8-改颜色与尺寸themedart-全表)
- [9. 改数据：表格与示例行](#9-改数据表格与示例行)
- [10. 改抽屉：三个面板](#10-改抽屉三个面板)
- [11. 改测试](#11-改测试)
- [12. 报错对照表](#12-报错对照表)
- [13. 需求速查索引](#13-需求速查索引)
- [14. 提交前检查清单](#14-提交前检查清单)

---

## 0. 三分钟上手

### 命令

```powershell
flutter analyze          # 必须 No issues found!
flutter test             # 必须 All tests passed!
flutter run -d windows   # 开发时热重载
flutter build windows --release
# 产物：build\windows\x64\runner\Release\app_ui.exe
```

### 改动的最小闭环

1. 想改的文案/控件，用 `Ctrl+Shift+F`（全局搜索）搜第 4 节表格里的锚点。
2. 改完跑 `flutter analyze` + `flutter test`。
3. 两条都过才算改对。

### 三条不要做

| 不要 | 原因 |
|---|---|
| `dart format` | 会重排 20+ 个文件，把 diff 搅成无法 review 的一团 |
| 在 `theme.dart` 之外写 `Color(0xFF...)` | 观感会漂移，改一处漏三处 |
| 直接删/改 `.ui` 文件 | 它是契约来源，Flutter 侧要跟着它改，而不是反过来 |

---

## 1. 工程地图

```
E:\xm\UI\
├── config.ui                  ← 设置抽屉的控件来源（Qt Designer XML）
├── untitled.ui                ← 主窗口的控件来源（Qt Designer XML）
├── lib\
│   ├── main.dart              入口 + 窗口设置（1048x682，最小 880x620）
│   ├── theme.dart             所有颜色 / 尺寸 / 时长 / 曲线 / PanelMetrics
│   ├── models.dart            表格列定义（3 套）+ 行模型 + 示例数据
│   ├── pages\
│   │   └── main_page.dart     页面骨架 + 全部状态持有者（1130 行）
│   └── widgets\
│       ├── object_names.dart  ★ .ui 的 objectName 常量表
│       ├── panel_controls.dart 桶文件（一行 import 拿到全部通用控件）
│       ├── panel_group_box.dart 卡片（对应 QGroupBox）
│       ├── panel\
│       │   ├── labeled_field.dart  [标签][输入框] 两格紧贴
│       │   ├── bare_field.dart     无标签输入框
│       │   ├── panel_button.dart   扁平按钮
│       │   ├── panel_dropdown.dart 下拉选择
│       │   ├── switch_row.dart     开关（32x16 轨道）
│       │   ├── check_box_row.dart  方框勾选（设置页已不用）
│       │   ├── section_label.dart  卡片标题
│       │   └── setting_atoms.dart  设置页的 `*` 提示文字
│       ├── drawer_panels.dart  三个抽屉面板（设置 / 个人中心 / 菜单）
│       ├── nav_bar.dart        底部图标条 + 抽屉外壳 + NavDestination 枚举
│       ├── flat_tab_bar.dart   工作区标签条
│       ├── setting_table.dart  小号表（只读、3 列、自适应高度）
│       ├── task_table.dart     主表格（+ body / header / menu / widths 四个 part）
│       ├── work_snack.dart     底部提示条
│       └── work_title_bar.dart 自绘标题条
└── test\                       8 个文件，69 个用例
```

### 数据流向

```
main_page.dart（唯一的状态持有者）
    │  持有：10 个 TextEditingController、5 个下拉值、4 个开关、
    │        3 份表格行、3 份选中集合、当前 Tab、当前抽屉
    │
    ├──→ 左栏四张卡片   _buildLoginCard / _buildInfoCard
    │                  _buildOptionCard / _buildActionCard
    │
    ├──→ 右侧三张表     _buildTable（按 objectName 区分）
    │
    └──→ 抽屉三个面板   _buildDrawerBody（switch on NavDestination）
```

**子组件一律无状态**：只负责画 + 转发回调。状态全部在 `_MainPageState` 里。
这条不是洁癖 —— 抽屉每次开关都会重建内容，状态放子组件里会丢。

---

## 2. 五条铁律

| # | 规则 | 违反后果 |
|---|---|---|
| 1 | 颜色、尺寸只写在 `lib/theme.dart` | 观感漂移，改一处漏三处 |
| 2 | 每个 `TextEditingController` 必须在 `dispose()` 里释放 | 内存泄漏 |
| 3 | 改界面状态必须包在 `setState(() { ... })` 里 | 点了没反应 |
| 4 | 不要运行 `dart format` | 重排 20+ 文件，diff 不可 review |
| 5 | 新增控件必须挂 `ValueKey(objectName)` | 测试无法按 .ui 名字定位 |

第 5 条是本轮新增的。理由见下一节。

---

## 3. objectName：Flutter 与 .ui 的唯一契约

### 为什么要有这一层

需求是「所有组件的 objectName 改为 ui 的 objectName」。散着改只能保证「看起来
差不多」—— `.ui` 已经改过三轮（`label_3` → `label_xhts`、`groupBox_3` →
`groupBox_shq`、`checkBox_qyxh_3` → `pushButton_shqdk`），每次都靠记忆同步，
必然跟丢。

所以 `lib/widgets/object_names.dart` 把 objectName 收成常量，两个用途：

```dart
// ① 控件挂 Key —— 测试用 byKey 定位，不依赖文案
LabeledField(
  key: const ValueKey<String>(kLineEditZh),
  label: '账户',
  controller: _lineEditZh,
)

// ② 状态字段名用同一套词的驼峰 —— 从 Dart 反查 .ui 不用猜
final TextEditingController _lineEditZh = TextEditingController();
```

### 常量表（节选，完整见文件）

**主窗口（untitled.ui）**

| 常量 | 值 | 说明 |
|---|---|---|
| `kTabWidgetGongzuoqu` | `tabWidget_gongzuoqu` | 标签容器 |
| `kTabYx` / `kTabDdxx` / `kTabWc` | `tab_yx` / … | 三个标签页 |
| `kTableWidgetYx` / `kTableWidgetDdxx` / `kTableWidgetWc` | … | 三张表 |
| `kGroupBoxLogin` | `groupBox_login` | 登录区卡片 |
| `kLineEditZh` / `kLineEditMm` / `kLineEditZfmm` | … | 账户 / 密码 / 支付密码 |
| `kPushButtonFs` / `kPushButtonDl` | `pushButton_fs` / `pushButton_dl` | 发送 / 登录 |
| `kGroupBoxXx` | `groupBox_xx` | 信息区卡片 |
| `kComboBoxXx` | `comboBox_xx` | 账号下拉 |
| `kLineEditCpxx2` | `lineEdit_cpxx_2` | key 输入框 |
| `kLineEditCpxx` / `kLineEditCpid` | … | 藏品信息 / 藏品Id |
| `kLineEditSl` / `kLineEditJg` | … | 数量 / 价格 |
| `kPushButtonCx` / `kPushButtonJr` | … | 查询 / 加入修改 |
| `kGroupBoxXxq` | `groupBox_xxq` | 选项区卡片 |
| `kComboBoxGn` / `kComboBoxFs` / `kComboBoxZf` | … | 功能 / 方式 / 支付 |
| `kGroupBox` | `groupBox` | 操作区卡片 |
| `kLineEditBf` | `lineEdit_bf` | 并发 |
| `kPushButtonKs` / `kPushButtonJs` | … | 开始 / 结束 |

**设置抽屉（config.ui）**

| 常量 | 值 | 所属区 |
|---|---|---|
| `kGroupBoxXhq` | `groupBox_xhq` | 小号区 |
| `kTableWidgetXh` | `tableWidget_xh` | 小号表 |
| `kCheckBoxQyxh` | `checkBox_qyxh` | 启用小号 |
| `kPushButtonXhhq` | `pushButton_xhhq` | 获取 |
| `kLabelXhts` | `label_xhts` | `*使用工具先获取小号数据` |
| `kGroupBoxHkq` | `groupBox_hkq` | 滑块区 |
| `kLabelHkts` | `label_hkts` | `*滑块需要配合使用工具` |
| `kPushButtonHklj` | `pushButton_hklj` | 链接 |
| `kCheckBoxQyhk` | `checkBox_qyhk` | 启用滑块 |
| `kGroupBoxShq` | `groupBox_shq` | 上号器区 |
| `kLineEditShqz` | `lineEdit_shqz` | 前缀 |
| `kPushButtonShqlj` | `pushButton_shqlj` | 链接 |
| `kPushButtonShqdk` | `pushButton_shqdk` | 断开 |
| `kGroupBoxDl` | `groupBox_4` | 代理区 |
| `kLabelDl` | `label_dl` | `*滑块需要配合使用工具` |
| `kPushButtonDllj` | `pushButton_dllj` | 链接 |
| `kCheckBoxQydl` | `checkBox_qydl` | 启用代理 |
| `kGroupBoxTz` | `groupBox` | 通知区 |
| `kComboBoxTzxx` | `comboBox_tzxx` | 息知 / wxpur / baerk |
| `kLineEditTz` | `lineEdit_tz` | 通知地址 |
| `kPushButtonDllj2` | `pushButton_dllj_2` | 测试 |
| `kCheckBoxQydl2` | `checkBox_qydl_2` | 启用代理 |

### 一个必须知道的坑

`.ui` 里「操作」区（untitled.ui）和「通知区」（config.ui）**都叫 `groupBox`**。
它们分属两个文件，在 Qt 里不冲突，所以照实保留同名。代价是：左栏可见 + 设置
抽屉打开时，`find.byKey(ValueKey('groupBox'))` 会命中**两个**。测试里要限定
作用域：

```dart
final Finder card = find.byKey(const ValueKey<String>(kGroupBoxTz)).last;
// 或
find.descendant(of: settingsPanel, matching: byKey(...))
```

### .ui 改了之后要做什么

```
1. 读新 .ui，找出改名的 objectName
2. 改 object_names.dart 里对应的常量值
3. 全局搜旧常量名 → 改引用（字段名可保留，只改常量值就不必动）
4. 若控件增删 → 改 drawer_panels.dart / main_page.dart
5. 跑 flutter test —— 按 objectName 的断言会立刻告诉你哪里断了
```

---

## 4. 改文案：全部锚点表

> 全部用 `Ctrl+Shift+F` 搜「锚点」列的内容。**不要记行号。**

### 4.1 左栏卡片标题 — `lib/pages/main_page.dart`

| 锚点 | 现文案 | objectName |
|---|---|---|
| `title: '登录区',` | 登录区 | `groupBox_login` |
| `title: '信息区',` | 信息区 | `groupBox_xx` |
| `title: '选项区',` | 选项区 | `groupBox_xxq` |
| `title: '操作',` | 操作 | `groupBox` |

### 4.2 左栏输入框标签与提示 — `main_page.dart`

| 锚点 | 现文案 | 备注 |
|---|---|---|
| `label: '账户',` | 账户 | hint `请输入账号` |
| `label: '密码',` | 密码 | hint `请输入密码`，`obscure: true` |
| `label: '支付密码',` | 支付密码 | hint `支付密码`，`obscure: true` |
| `label: '藏品信息',` | 藏品信息 | hint `自己填写或选择` |
| `label: '藏品Id',` | 藏品Id | hint `自己填写或选择` |
| `label: '数量',` | 数量 | `keyboardType: number` |
| `label: '价格',` | 价格 | `keyboardType: number` |
| `label: '并发',` | 并发 | `keyboardType: number` |

> **标签最多 4 个字**。`LabeledField` 的标签格 60 宽，4 字中文约 50px 刚好；
> 超出会被 `FittedBox` 缩小，再长变省略号。

### 4.3 左栏按钮文字 — `main_page.dart`

| 锚点 | 现文案 | objectName | 现在可点？ |
|---|---|---|---|
| `label: '发送',` | 发送 | `pushButton_fs` | 否（`onPressed: null`） |
| `label: '登录',` | 登录 | `pushButton_dl` | 是（空实现） |
| `label: '查询',` | 查询 | `pushButton_cx` | 是（空实现） |
| `label: '加入修改',` | 加入修改 | `pushButton_jr` | 是（空实现） |
| `label: '开始',` | 开始 | `pushButton_ks` | 未运行时 |
| `label: '结束',` | 结束 | `pushButton_js` | 运行中时 |

### 4.4 选项区下拉 — `main_page.dart`

| 锚点 | 现文案 | objectName |
|---|---|---|
| `label: '功能',` | 功能 | `comboBox_gn` |
| `label: '方式',` | 方式 | `comboBox_fs` |
| `label: '支付',` | 支付 | `comboBox_zf` |

下拉候选在同文件的 `_comboBoxGnItems` / `_comboBoxFsItems` /
`_comboBoxZfItems`（`static const List<String>`）。

### 4.5 工作区标签 — `main_page.dart`

```dart
static const List<String> _tabTitles = <String>['运行', '订单信息', '完成'];
```

改这里的同时，三张表的 `objectName` 不用动（`kTableWidgetYx` 等），但
`_buildTable` 的调用顺序要与 `_tabTitles` 对应。

### 4.6 设置抽屉 — `lib/widgets/drawer_panels.dart`

| 锚点 | 现文案 | 所属 |
|---|---|---|
| `title: '小号区',` | 小号区 | ① |
| `label: '启用小号',` | 启用小号 | ① |
| `buttonLabel: '获取',` | 获取 | ① |
| `tip: '*使用工具先获取小号数据',` | `*使用工具…` | ① |
| `title: '滑块区',` | 滑块区 | ② |
| `label: '启用滑块',` | 启用滑块 | ② |
| `buttonLabel: '链接',` | 链接 | ② |
| `tip: '*滑块需要配合使用工具',` | `*滑块…` | ② |
| `title: '上号器区',` | 上号器区 | ③ |
| `subtitle: '格式：前缀-手机号-密码-支付密码',` | 副标题 | ③ |
| `label: '前缀',` | 前缀 | ③ |
| `label: '链接',` | 链接 | ③ |
| `label: '断开',` | 断开 | ③ |
| `title: '代理区',` | 代理区 | ④ |
| `text: '*滑块需要配合使用工具',` | `*滑块…` | ④ |
| `label: '链接',` | 链接 | ④ |
| `label: '启用代理',` | 启用代理 | ④ |
| `title: '通知区',` | 通知区 | ⑤ |
| `label: '测试',` | 测试 | ⑤ |
| `label: '启用代理',` | 启用代理 | ⑤ |

> **注意**：设置页里 `'链接'` 出现 **3 次**、`'启用代理'` 出现 **2 次**、
> `'*滑块需要配合使用工具'` 出现 **2 次**（代理区的 `label_dl` 在 .ui 里就是
> 从滑块区复制过来的）。改文案时用 `replace_all` 或按上下文区分。

### 4.7 个人中心与菜单 — `drawer_panels.dart`

| 锚点 | 现文案 |
|---|---|
| `label: '退出登录',` | 退出登录 |
| `label: '使用说明',` | 使用说明 |
| `label: '运行日志',` | 运行日志 |
| `label: '检查更新',` | 检查更新 |
| `label: '关于',` | 关于 |

### 4.8 表格右键菜单 — `lib/widgets/task_table_menu.dart`

| 锚点 | 现文案 |
|---|---|
| `label: '全选',` | 全选 |
| `label: '反选',` | 反选 |
| `label: '删除选中',` | 删除选中（红色） |
| `label: '删除成功',` | 删除成功（红色） |

### 4.9 窗口标题

两个地方要同时改：

1. `lib/theme.dart` → `const String kWindowTitle = '阿萨德';`
2. 无需改 `main.cpp` —— 原生层不设标题，标题由 `WorkTitleBar` 自绘。

---

## 5. 改控件：常用组件的完整参数

全部从 `package:app_ui/widgets/panel_controls.dart` 一处导入。

### PanelGroupBox — 卡片

```dart
PanelGroupBox(
  objectName: kGroupBoxLogin,   // .ui 的 objectName，挂 ValueKey
  title: '登录区',               // 卡片标题（主色 w600 小标题）
  subtitle: '格式：…',           // 可选，标题下的辅助说明（换行显示）
  padding: m.groupBoxPadding,   // 内边距，跟 PanelMetrics 档位走
  sectionGap: m.sectionGap,     // 标题与首个控件的间距
  child: Column(...),
)
```

`subtitle` 只有「上号器区」用 —— `.ui` 把格式说明并进了 `groupBox_shq.title`，
24 个字单行必然被截断，所以拆两行。

### LabeledField — 带标签输入框

```dart
LabeledField(
  key: const ValueKey<String>(kLineEditZh),
  label: '账户',                 // 左侧标签格文案（≤4 字）
  controller: _lineEditZh,       // 必须由页面持有并 dispose
  hint: '请输入账号',             // 空值提示（.ui 的 placeholderText）
  labelWidth: kLabelWidth,       // 标签格宽度，默认 60
  obscure: false,                // true = 密码框
  keyboardType: TextInputType.number,
  onSubmitted: (String v) {},    // 回车
  onChanged: (String v) {},      // 每次输入
  trailing: Widget?,             // 输入框右侧附加控件
  enabled: true,                 // false = 禁用态
  hasError: false,               // true = 红框加粗
)
```

行高固定 `kRowHeight`（30），标签格与输入格共用 1px 边框，圆角只给外侧两角。

### BareField — 无标签输入框

```dart
BareField(
  key: const ValueKey<String>(kLineEditCpxx2),
  controller: _lineEditCpxx2,
  hint: 'key',
  enabled: false,      // .ui 里 lineEdit_cpxx_2 就是 disabled
  center: true,        // 文字居中（.ui 的 AlignCenter）
  onChanged: (String v) {},
)
```

用于 `.ui` 里「不配 QLabel、独占整行」的输入框。目前两处：信息区的 key 框、
通知区的地址框。

### PanelButton — 按钮

```dart
PanelButton(
  key: const ValueKey<String>(kPushButtonDl),
  label: '登录',
  onPressed: () {},          // null = 禁用（不响应悬停/按下）
  primary: true,             // 主色描边+文字，主操作用
  accentColor: WorkColors.warning,  // 自定义强调色
  height: kCompactButtonHeight,     // 默认 kRowHeight(30)
)
```

### PanelDropdown — 下拉

```dart
PanelDropdown(
  key: const ValueKey<String>(kComboBoxGn),
  value: _comboBoxGn,              // 必须恰好存在于 items 中，否则断言失败
  items: _comboBoxGnItems,
  onChanged: (String? v) {},       // null = 禁用
  hint: '选择已保存账号',           // 空列表时的提示
  borderRadius: BorderRadius.only(...),  // 与标签格拼接时只圆右侧两角
)
```

### SwitchRow — 开关

```dart
SwitchRow(
  key: const ValueKey<String>(kCheckBoxQyxh),
  label: '启用小号',        // 允许空串（只剩轨道，需配 tooltip）
  value: checkBoxQyxh,
  onChanged: (bool v) => setState(() => checkBoxQyxh = v),
  enabled: true,
  tooltip: '…',            // label 为空时的说明
)
```

整行可点（不只开关本体）。轨道 32x16、圆钮 12、滑动 `kStateDuration`。

### SettingTip — 设置页的 `*` 提示

```dart
SettingTip(
  key: const ValueKey<String>(kLabelXhts),
  text: '*使用工具先获取小号数据',
  inline: true,   // true = 与其它控件同排：单行 + FittedBox 缩放，绝不折行
)
```

`inline: false`（默认）允许折两行。`inline: true` 用于和开关、按钮挤一排时 ——
折行会把整排顶高，破坏卡片等高。

### SectionLabel — 卡片标题

一般不用直接调，`PanelGroupBox` 内部已用。

```dart
SectionLabel(text: '登录区')
```

---

## 6. 加控件：四个可照抄的配方

### 6.1 加输入框（五步）

> 下面的 `kLineEditBz` 是**举例用的新名字**，工程里目前没有 —— 照着加的时候
> 换成你实际要加的 objectName。

**① 定 objectName** — 若 `.ui` 里已有对应控件，把它的名字加进
`lib/widgets/object_names.dart`：

```dart
/// `lineEdit_bz` —— 备注。
const String kLineEditBz = 'lineEdit_bz';
```

**② 加控制器** — `main_page.dart` 的 `_lineEditBf` 下面：

```dart
  /// 备注输入框（.ui 的 lineEdit_bz）。
  final TextEditingController _lineEditBz = TextEditingController();
```

**③ 注册释放** — 同文件 `dispose()` 里，`_lineEditBf.dispose();` 下面：

```dart
    _lineEditBz.dispose();
```

**④ 加到界面** — `_buildInfoCard` 里「价格」那个 `LabeledField` 之后：

```dart
          SizedBox(height: m.rowGap),
          LabeledField(
            key: const ValueKey<String>(kLineEditBz),
            label: '备注',
            controller: _lineEditBz,
            hint: '选填',
          ),
```

**⑤ 验证** — `flutter analyze` + `flutter test`

> 若新输入框要在抽屉里实时回显，还要在 `initState` 里挂
> `_lineEditBz.addListener(_onSettingFieldChanged);`，并在 `dispose` 里先摘监听。

### 6.2 加按钮（三步）

**① 写方法** — `main_page.dart` 的 `_stopRun` 之后：

```dart
  /// 点「清空」：把几个输入框恢复默认值。
  void _doClear() {
    setState(() {
      _lineEditZh.clear();
      _lineEditMm.clear();
      _lineEditSl.text = '1';
      _lineEditJg.text = '100';
    });
    _snack('已清空');
  }
```

**② 加到布局** — `_buildActionCard` 里「开始 / 结束」那一行，第二个
`Expanded` 之后：

```dart
              const SizedBox(width: 8),
              Expanded(
                child: PanelButton(
                  label: '清空',
                  height: kCompactButtonHeight,
                  onPressed: _doClear,
                ),
              ),
```

**③ 验证** — 三个按钮会自动三等分。太挤就把 `width: 8` 改小。

### 6.3 加一个开关（四步）

> `kCheckBoxQyzd` 同样是**举例用的新名字**，照着加时换成实际的 objectName。

**① objectName** — `object_names.dart` 加 `const String kCheckBoxQyzd = 'checkBox_qyzd';`

**② 状态字段** — `main_page.dart` 的 `_checkBoxQydl2` 下面：

```dart
  bool _checkBoxQyzd = false;
```

**③ 面板参数** — `SettingsPanel` 的构造函数与字段列表各加两项：

```dart
    required this.checkBoxQyzd,
    required this.onCheckBoxQyzdChanged,
```

```dart
  final bool checkBoxQyzd;
  final ValueChanged<bool> onCheckBoxQyzdChanged;
```

**④ 加到某个卡片** — `drawer_panels.dart` 里对应 `_buildXxxCard()`：

```dart
            SwitchRow(
              key: const ValueKey<String>(kCheckBoxQyzd),
              label: '启用自动',
              value: checkBoxQyzd,
              onChanged: onCheckBoxQyzdChanged,
            ),
```

**⑤ 页面接线** — `main_page.dart` 的 `_buildDrawerBody` 里 `SettingsPanel(...)`：

```dart
        checkBoxQyzd: _checkBoxQyzd,
        onCheckBoxQyzdChanged: (bool v) => setState(() => _checkBoxQyzd = v),
```

### 6.4 加一个抽屉（四步）

> `kDrawerWidthHelp` 是**举例用的新常量**，工程里目前只有三档
> （`kDrawerWidthSettings` / `kDrawerWidthProfile` / `kDrawerWidthMenu`）。
> 新增抽屉时可以先复用这三档之一。

**① enum** — `nav_bar.dart` 的 `NavDestination` 加一行（**必须带宽度**）：

```dart
  help('帮助', Icons.help_outline, Icons.help, kDrawerWidthMenu),
```

**② 宽度常量** — `theme.dart` 里已有三档，可直接复用，或新增：

```dart
const double kDrawerWidthHelp = 240;   // 举例；新增后记得在 enum 里用它
```

**③ 面板** — `drawer_panels.dart` 加一个 `HelpPanel`：

```dart
class HelpPanel extends StatelessWidget {
  const HelpPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text('帮助内容待补');
  }
}
```

**④ 接线** — `main_page.dart` 的 `_buildDrawerBody` 里 `switch` 加分支：

```dart
      NavDestination.help => const HelpPanel(),
```

> `switch` 是穷举的：加了 enum 项不加分支，`flutter analyze` 会直接报错。
> 这是故意的 —— 避免「点了图标抽屉是空的」。

---

## 7. 改布局：三种排布范式

### 范式 A：纵向流式（左栏卡片、设置卡片）

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  mainAxisSize: MainAxisSize.min,
  children: <Widget>[
    LabeledField(...),
    SizedBox(height: m.rowGap),
    LabeledField(...),
    SizedBox(height: m.preButtonGap),
    Row(children: <Widget>[Expanded(...), SizedBox(width: 8), Expanded(...)]),
  ],
)
```

卡片宽度由父容器决定，**不要**写死宽度 —— 否则抽屉变宽时右侧会留空白。

### 范式 B：控件同排（设置页的代理区 / 通知区）

需求要求「所有控件在同一行」。做法是：**固定项给固定宽，可伸缩项给 Expanded**。

```dart
SizedBox(
  height: kRowHeight,   // 整行高度由最高的控件锁住
  child: Row(
    children: <Widget>[
      const Expanded(child: SettingTip(text: '…', inline: true)),  // 可伸缩
      const SizedBox(width: kSettingInlineGap),
      _CompactButton(objectName: kPushButtonDllj, label: '链接', ...),  // 固定 64
      const SizedBox(width: kSettingInlineGap),
      SwitchRow(label: '启用代理', ...),  // 按内容自适应
    ],
  ),
)
```

**宽度预算要先算**。抽屉内容区 311 − 卡片内边距 20 = **291**：

| 区 | 固定项 | 剩给可伸缩项 |
|---|---|---|
| 上号器区 | 按钮 64×2 + 间距 12 = 140 | 151（标签格 44 + 输入框 107） |
| 代理区 | 按钮 64 + 间距 12 + 开关约 100 = 176 | 115（全给提示） |
| 通知区 | 按钮 64 + 间距 18 + 开关约 100 = 182 | 109（下拉 72 + 输入框 37） |

> **踩过的坑**：通知区最初给下拉按 3:4 分配 → 48px → 实机显示成「息...」。
> 原因：`DropdownButton` 内部有个 24px 的箭头图标槽，48 扣掉它只剩 24。
> 所以下拉改成固定 `kSettingNotifyComboWidth = 72`。

### 范式 C：自适应高度（小号表）

```dart
height: kSettingTableHeaderHeight
      + kSettingTableRowHeight * _visibleRows
      + kSettingTableBorderWidth * 2,
```

`_visibleRows` 的规则：空表 → `kSettingTableMinRows`（2 行），有数据 → 实际
条数封顶 `kSettingTableMaxRows`（5 行）。**用条数判断，不要用「有没有溢出」** ——
后者要等布局完成才知道，会出现「先矮后高」的一帧跳变。

### 左栏的自适应档位

左栏四张卡片在 620 高的可用空间里放不下，所以有三档空白压缩（控件高度与字号
一个像素都不动）：

| 档 | rowGap | cardGap | sectionGap | preButtonGap |
|---|---|---|---|---|
| `normal` | 7 | 12 | 6 | 8 |
| `compact` | 5 | 5 | 3 | 4 |
| `dense` | 2 | 1 | 1 | 2 |

`_buildLeftPanel` 的 `LayoutBuilder` 量真实可用高度，从 `normal` 开始试，
第一个 `contentHeight <= cardsAvail` 的胜出。三档都装不下才让左栏滚。

---

## 8. 改颜色与尺寸：theme.dart 全表

### 8.1 颜色

改主色（那个绿色）一行搞定，全工程 30+ 处跟着变（按钮、聚焦边框、选中条、
下划线、滚动条）：

```dart
static const Color primary = Color(0xFF3AAF9F);
```

`0xFF3AAF9F` 拆开：`FF` = 不透明、`3A` = 红、`AF` = 绿、`9F` = 蓝。
换蓝色用 `0xFF2E7DD1`。

| 常量 | 值 | 用途 |
|---|---|---|
| `primary` | `0xFF3AAF9F` | 主色 |
| `primaryDark` | `0xFF2E9184` | 悬停深一档 |
| `primarySoft` | `0x1F3AAF9F` | 12% 主色底 |
| `brand` | `0xFF008000` | 卡片标题 |
| `surface` | `0xFFFCFCFE` | 整窗底色 |
| `panel` | `0xFFF5F6F7` | 卡片/标签格底色 |
| `fieldFill` | `0xFFFFFFFF` | 输入框底色 |
| `fieldFillFocused` | `0xFFF2F8F7` | 聚焦底色 |
| `border` | `0xFFD8DBDE` | 边框 |
| `headerFill` | `0xFFEFF3F2` | 表头 |
| `rowAlt` | `0xFFF8FAFA` | 隔行 |
| `textPrimary` | `0xFF2B2B2B` | 主文字 |
| `textHint` | `0xFF7A7A7A` | 提示 |
| `textMuted` | `0xFF9A9A9A` | 辅助 |
| `danger` / `error` | `0xFFE0525A` / `0xFFD64545` | 危险 / 错误 |
| `running` / `idle` | `0xFF2E9184` / `0xFF9A9A9A` | 运行中 / 空闲 |
| `warning` | `0xFFD98324` | 警告 |

**加新颜色的正确做法**：`AppColors` 里定义，`WorkColors` 里加别名，
用的时候 `WorkColors.xxx`。

```dart
// AppColors 里
/// 提示：需要注意。
static const Color notice = Color(0xFFE8A33D);

// WorkColors 里
static const Color notice = AppColors.notice;
```

### 8.2 尺寸 — 全局基础

| 常量 | 值 | 控制什么 |
|---|---|---|
| `kRowHeight` | 30 | 输入框 / 按钮 / 下拉高度 |
| `kRowGap` | 7 | 常规档行间距 |
| `kPanelWidth` | 212 | 左栏宽度 |
| `kPanelPadding` | 12 | 页面外边距 |
| `kLabelWidth` | 60 | 左标签格宽度 |
| `kRadius` | 3 | 圆角 |
| `kTitleBarHeight` | 38 | 标题条高 |
| `kHeaderHeight` | 40 | 表头高 |
| `kRowItemExtent` | 34 | 表格行高 |
| `kTabBarHeight` | 34 | Tab 栏高 |
| `kCardGap` | 12 | 卡片间距 |
| `kGroupBoxPadding` | `(10,10,10,12)` | 卡片内边距 |
| `kSectionGap` | 6 | 标题与首控件间距 |
| `kCompactButtonHeight` | 23 | 紧凑按钮高 |
| `kSmallButtonWidth/Height` | 41 / 21 | 查询小按钮 |
| `kScrollThickness/Radius` | 6 / 3 | 滚动条 |
| `kFontBody/Title/Hint` | 12.5 / 13 / 12 | 字号 |

### 8.3 尺寸 — 设置页专用

| 常量 | 值 | 控制什么 |
|---|---|---|
| `kSettingCardGap` | 12 | 五张卡片间距 |
| `kSettingRowGap` | 8 | 卡片内行间距 |
| `kSettingInlineGap` | 6 | 同排控件之间的水平间距 |
| `kSettingActionButtonWidth` | 64 | 设置页按钮宽 |
| `kSettingLoaderLabelWidth` | 44 | 上号器区标签格（比 60 窄） |
| `kSettingNotifyComboWidth` | 72 | 通知区下拉宽 |
| `kSettingTableHeaderHeight` | 26 | 小号表表头 |
| `kSettingTableRowHeight` | 24 | 小号表行高 |
| `kSettingTableNoWidth` | 34 | no 列宽 |
| `kSettingTableMinRows` | 2 | 空表显示行数 |
| `kSettingTableMaxRows` | 5 | 封顶行数 |
| `kSwitchWidth/Height/Gap` | 32 / 16 / 8 | 开关 |

### 8.4 尺寸 — 抽屉

| 常量 | 值 | 控制什么 |
|---|---|---|
| `kDrawerWidthSettings` | 360 | 设置抽屉（最宽，五张卡片） |
| `kDrawerWidthProfile` | 260 | 个人中心 |
| `kDrawerWidthMenu` | 200 | 菜单（最窄） |
| `kDrawerDuration` | 300ms | 滑入 |
| `kDrawerExitDuration` | 220ms | 滑出（比滑入快 1/4） |
| `kDrawerScrimAlpha` | 0.18 | 遮罩浓度 |
| `kDrawerHeaderHeight` | 40 | 抽屉标题栏 |
| `kDrawerContentPadding` | `(14,12,14,14)` | 抽屉内边距 |
| `kProfileLogoutWidth` | 96 | 退出登录按钮宽 |
| `kMenuItemGap` | 2 | 菜单项间距 |
| `kNavButtonSize/IconSize/Gap` | 26 / 16 / 6 | 底部图标条 |

**抽屉宽度为什么分三档**：三个面板装的东西差别很大。设置页要放五张卡片（通知区
一行四件控件），360 刚好；个人中心只有一个头像 + 两行字 + 一个按钮，360 会让
右侧空出近 200px；菜单只有四个短条目。所以按内容定档，见 `NavDestination.width`。

### 8.5 窗口尺寸

```dart
// theme.dart
const double kDesignWidth = 1048;
const double kDesignHeight = 682;
const double kMinWidth = 880;
const double kMinHeight = 620;
```

改默认窗口大小要**同时**改 `windows\runner\main.cpp`：

```cpp
constexpr int kWindowWidth = 1048;
constexpr int kWindowHeight = 682;
```

### 8.6 动效

| 常量 | 值 | 用途 |
|---|---|---|
| `kHoverDuration` | 90ms | 悬停变色 |
| `kPressDuration` | 60ms | 按下 |
| `kStateDuration` | 150ms | 开关滑动、选中切换 |
| `kSlideInCurve` | `easeOutCubic` | 抽屉进场（快起慢收） |
| `kSlideOutCurve` | `easeInCubic` | 抽屉退场（慢起加速） |

---

## 9. 改数据：表格与示例行

### 9.1 三张表的列定义 — `lib/models.dart`

```dart
const List<TaskColumn> kRunColumns = <TaskColumn>[
  TaskColumn(field: TaskField.no, flex: 9, minWidth: 44),
  TaskColumn(field: TaskField.phone, flex: 14, minWidth: 60),
  // …
];
```

| 字段 | 含义 |
|---|---|
| `field` | 取哪一列数据（`TaskField` 枚举） |
| `flex` | 宽度权重（三张表各自归一化） |
| `minWidth` | 最小宽度，低于它会被截断 |
| `tooltip` | `true` = 内容超长时悬停显示全文 |

三套列定义：`kRunColumns`（9 列）、`kOrderColumns`（8 列，数量/价格换成 Oid）、
`kDoneColumns`（9 列，多一列支付链接）。

**加一列**：`TaskField` 加枚举值 → `TaskRow` 加字段 → 对应
`kRunColumns` / `kOrderColumns` / `kDoneColumns` 里加 `TaskColumn` →
`task_table_body.dart` 的取值 switch 加分支（穷举，漏了会报错）。

### 9.2 示例数据 — `models.dart`

```dart
const List<TaskRow> kDemoRunRows = <TaskRow>[ /* … */ ];
const List<TaskRow> kDemoOrderRows = <TaskRow>[ /* … */ ];
const List<TaskRow> kDemoDoneRows = <TaskRow>[ /* … */ ];
```

### 9.3 小号表数据 — `lib/widgets/setting_table.dart`

```dart
const List<String> kSubAccountColumns = <String>['no', 'phone', 'token'];

const List<SubAccount> kDemoSubAccounts = <SubAccount>[
  SubAccount(no: '1', phone: '13800138000', token: 'tk_9f2a'),
  // … 共 10 条
];
```

列名取自 `.ui` 的 `<column><property name="text">`。

### 9.4 下拉候选 — `main_page.dart`

```dart
static const List<String> _comboBoxGnItems = <String>['默认模式', '一键下单'];
static const List<String> _comboBoxFsItems = <String>['锁单', '提取支付链接', '余额支付'];
static const List<String> _comboBoxZfItems = <String>['易宝自动支付', /* … */];
static const List<String> _comboBoxTzxxItems = <String>['息知', 'wxpur', 'baerk'];
```

默认选中值在下面的 `String? _comboBoxGn = '默认模式';` 等。**默认值必须存在于
候选列表里**，否则 `DropdownButton` 断言失败。

---

## 10. 改抽屉：三个面板

### 10.1 结构

```dart
// nav_bar.dart
enum NavDestination {
  settings('设置', …, kDrawerWidthSettings),   // 360
  profile('个人中心', …, kDrawerWidthProfile),  // 260
  menu('菜单', …, kDrawerWidthMenu);            // 200
  final double width;
}

// main_page.dart
Widget _buildDrawerBody(NavDestination d) => switch (d) {
      NavDestination.settings => SettingsPanel(...),
      NavDestination.profile => ProfilePanel(...),
      NavDestination.menu => MenuPanel(...),
    };
```

### 10.2 改某个抽屉的宽度

`theme.dart` 里改对应的 `kDrawerWidthXxx`。宽度由 `NavDestination.width`
自动取，`DrawerHost` 不需要改。

### 10.3 换图标

`nav_bar.dart` 的 enum，三个参数分别是：中文名、未选中图标、选中图标。
去 fonts.google.com/icons 找新图标替换 `Icons.xxx`。

### 10.4 设置页五个分区的结构

```
SettingsPanel.build
├── _buildSubAccountCard()   ① 小号区   表格 + _ActionRow(开关/按钮/提示)
├── _buildSliderCard()       ② 滑块区   _ActionRow
├── _buildLoaderCard()       ③ 上号器区 输入框 + 链接 + 断开（三件同排）
├── _buildProxyCard()        ④ 代理区   提示 + 链接 + 开关（三件同排）
└── _buildNotifyCard()       ⑤ 通知区   下拉 + 输入框 + 测试 + 开关（四件同排）
```

`_ActionRow` 是 ①② 共用的「开关 + 按钮 + 提示」三件同排组件，
`_CompactButton` 是四个按钮共用的 64x23 定宽按钮。

---

## 11. 改测试

### 11.1 现状

```
test\settings_test.dart          20 个  设置页（控件齐全 / objectName / 同排 / 交互 / 布局）
test\setting_layout_test.dart    11 个  设置页几何（卡片铺满 / 列宽 / 表格高度 / 同排对齐）
test\regression_test.dart         9 个  回归（抽屉回显 / 滚动条 / 极窄窗口 / 提示去重 / 动画 / 遮罩）
test\nav_drawer_test.dart         8 个  抽屉（滑出 / 状态机 / 三档宽度 / 内容完整）
test\task_table_widths_test.dart  7 个  表格列宽算法
test\interaction_test.dart        6 个  左栏交互
test\widget_test.dart             5 个  整体冒烟
test\layout_alignment_test.dart   3 个  左栏对齐
                                  ───
                                  69 个
```

### 11.2 按 objectName 定位（推荐写法）

```dart
/// 按 .ui 的 objectName 找控件。
Finder byObjectName(String objectName) =>
    find.byKey(ValueKey<String>(objectName));

// 用
expect(byObjectName(kLineEditShqz), findsOneWidget);
```

**不要**用 `find.text('前缀')` —— 文案会改，objectName 是契约。

### 11.3 量几何（同排 / 对齐）

```dart
final Finder card = byObjectName(kGroupBoxTz).last;  // 通知区（与操作区同名）
final Rect combo = tester.getRect(
  find.descendant(of: card, matching: byObjectName(kComboBoxTzxx)),
);
final Rect field = tester.getRect(
  find.descendant(of: card, matching: byObjectName(kLineEditTz)),
);

// 纵向中心一致 = 同一行
expect(field.center.dy, closeTo(combo.center.dy, 1.5));
// 水平顺序
expect(combo.right, lessThanOrEqualTo(field.left));
```

### 11.4 容器尺寸要量对目标

| 想量什么 | 量谁 | 坑 |
|---|---|---|
| 列宽 | `SizedBox`（`_cellSlot` 里那个） | 量 `Text` 只得到文字宽，扣掉了 6px 内边距 |
| 表格高 | `SubAccountTable` 本身 | — |
| 卡片宽 | `PanelGroupBox` | 量 `SlideOutDrawer` 会得到整栏宽 |
| 按钮宽 | 外层 `SizedBox` | 量 `PanelButton` 内部 `Container` 会差边框 |

### 11.5 加一条测试

```dart
testWidgets('新增控件的描述', (WidgetTester tester) async {
  setSurface(tester, kDesignWidth, kDesignHeight);
  await tester.pumpWidget(wrap());
  await tester.pumpAndSettle();
  await openSettings(tester);

  expect(byObjectName(kLineEditBz), findsOneWidget);
  expect(tester.takeException(), isNull, reason: '不该溢出');
});
```

`wrap()` / `setSurface()` / `openSettings()` 在每个测试文件头部都有定义。

---

## 12. 报错对照表

### `RenderFlex overflowed by X pixels`

内容装不下。按顺序试：

1. **收紧密排档** — `theme.dart` 的 `kDenseRowGap` / `kDenseCardGap` 改小 1
2. **加第四档** — `dense` 下面照抄一个 `ultraDense`，并在
   `byDescendingSpace` 列表末尾加上
3. **减少固定宽** — 若是同排布局，把某个固定 `SizedBox(width:)` 改成 `Expanded`
4. **降字号** — 最后手段，会破坏与其它控件的一致性

### `A ScrollController is required when Scrollbar.thumbVisibility is true`

`Scrollbar` 开了 `thumbVisibility: true` 就必须显式传 `controller`。
在 `State` 里持有（不能在 `build` 里现造，否则每帧换新实例、滚动位置重置）。

### `A TextEditingController was used after being disposed`

用了已销毁的输入框。检查 `await` 之后有没有 `if (!mounted) return;`。

### `setState() called after dispose()`

页面关了还在刷新。异步回调里加：

```dart
if (!mounted) return;
setState(() { ... });
```

### `There should be exactly one item with [DropdownButton]'s value`

`PanelDropdown` 的 `value` 不在 `items` 里。检查默认值是否存在于候选列表。

### `The named parameter 'xxx' isn't defined`

组件没这个参数。去看对应文件的构造函数（第 5 节有全部参数表）。

### `Switch` / `CheckBoxRow` 相关报错

设置页的勾选框已全部换成 `SwitchRow`。若看到 `CheckBoxRow`，那是旧代码残留 ——
`check_box_row.dart` 还在（左栏可能用），但设置页不该出现。

### 点了没反应

1. 回调是不是 `() {}`（空的）？
2. 有没有包 `setState`？
3. 按钮是不是 `onPressed: null`（禁用）？
4. 开关的 `onChanged` 是不是没接到 `_buildDrawerBody` 的 `setState`？

### 找不到 objectName

`object_names.dart` 里的常量值与 `.ui` 不一致。核对 `.ui` 的
`<widget class="..." name="...">`。

---

## 13. 需求速查索引

| 我想… | 文件 | 搜什么 |
|---|---|---|
| 改卡片标题 | main_page.dart | `title: '登录区'` 等 |
| 改输入框标签 | main_page.dart | `label: '账户'` 等 |
| 改按钮文字 | main_page.dart | `label: '登录'` 等 |
| 给按钮加逻辑 | main_page.dart | `onPressed: () {}` |
| 改 Tab 名字 | main_page.dart | `_tabTitles` |
| 改下拉候选 | main_page.dart | `_comboBoxGnItems` 等 |
| 改表格列 | models.dart | `kRunColumns` |
| 改示例数据 | models.dart | `kDemoRunRows` |
| 改小号表数据 | setting_table.dart | `kDemoSubAccounts` |
| 改设置页文案 | drawer_panels.dart | `title: '小号区'` 等 |
| 改设置页控件 | drawer_panels.dart | `_buildSubAccountCard` 等 |
| 改菜单项 | drawer_panels.dart | `label: '使用说明'` |
| 改主色 | theme.dart | `static const Color primary` |
| 改行高 | theme.dart | `kRowHeight` |
| 改左栏宽 | theme.dart | `kPanelWidth` |
| 改窗口标题 | theme.dart | `kWindowTitle` |
| 改窗口大小 | theme.dart + main.cpp | `kDesignWidth` / `kWindowWidth` |
| 改抽屉宽度 | theme.dart | `kDrawerWidthSettings` |
| 改抽屉速度 | theme.dart | `kDrawerDuration` |
| 加底部图标 | nav_bar.dart + main_page.dart | `NavDestination` / `_buildDrawerBody` |
| 加 objectName | object_names.dart | 按 .ui 的分组追加 |
| 查某个控件叫什么 | object_names.dart | 按中文名搜注释 |

---

## 14. 提交前检查清单

```
□ flutter analyze  → No issues found!
□ flutter test     → All tests passed!（69 个）
□ 新 controller 有 dispose()
□ 新控件挂了 ValueKey(objectName)
□ object_names.dart 与 .ui 一致
□ 颜色没写死在 theme.dart 之外
□ 没跑 dart format
□ 窗口拉到 880x620 试过，没黄黑警示条
□ 三个抽屉各开一次，内容完整不溢出
```

### 提交信息格式

```
feat: 一句话说做了什么

- 具体改动 1
- 具体改动 2

验证：flutter analyze 无问题；flutter test N 个全通过
```

### 推送到 GitHub

```powershell
git add -A
git commit -m "feat: …"
git push origin main
```

远端：`git@github.com:li200-200/NFTui.git`（SSH，已配好密钥）。

---

## 附：历史文档

`UI_GUIDE.md` 已过期，保留仅作参考。它的行号全部漂移，且仍在讲：

- `CheckBoxRow`（设置页已换成 `SwitchRow`）
- 单一 `kDrawerWidth`（已拆成三档）
- 不存在的 `_buildDrawer()`（现在是 `_buildDrawerBody(NavDestination)`）
- 第 294 行的 `kDrawerWidth`（现在在 448~456 行，且有三个值）

**以本文档为准。**
