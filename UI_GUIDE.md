# 改 UI 速查手册

给不熟悉 Flutter 的人用。**改界面看第一节，改颜色看第二节，报错看第三节。**

改完永远跑这两条：

```
flutter analyze
flutter test
```

看到 `No issues found!` + `All tests passed!` 才算改对。

---

## 铁律

| # | 规则 | 违反后果 |
|---|---|---|
| 1 | 颜色、尺寸只写在 `lib/theme.dart` | 观感漂移，改一处漏三处 |
| 2 | 每个 `TextEditingController` 必须 `dispose()` | 内存泄漏 |
| 3 | 改界面状态必须包在 `setState(() { ... })` | 点了没反应 |
| 4 | 不要运行 `dart format` | 会重排 8 个文件 |
| 5 | 行号会变，**用 Ctrl+F 搜内容**比记行号可靠 | — |

---

## 一、改界面：`lib/pages/main_page.dart`

### 卡片标题

搜 `title: '`

| 内容 | 行号 |
|---|---|
| `title: '登录区',` | 446 |
| `title: '信息区',` | 507 |
| `title: '选项区',` | 595 |
| `title: '操作',` | 637 |

### 输入框标签

搜 `label: '`

| 内容 | 行号 | 内容 | 行号 |
|---|---|---|---|
| 账户 | 454 | 藏品信息 | 558 |
| 密码 | 460 | 藏品Id | 564 |
| 支付密码 | 468 | 数量 | 570 |
| 并发 | 645 | 价格 | 576 |

标签**最多 4 个字**。超了会被自动缩小，再长变省略号。

### 按钮文字

搜 `label: '`

| 内容 | 行号 |
|---|---|
| 发送 | 480 |
| 登录 | 490 |
| 查询 | 532 |
| 加入修改 | 583 |
| 开始 | 656 |
| 结束 | 665 |

### 按钮加逻辑

现在都是 `onPressed: () {}`（空的大括号 = 点了没反应）。

| 按钮 | 行号 | 改成 |
|---|---|---|
| 登录 | 494 | `onPressed: _doLogin,` |
| 查询 | 534 | `onPressed: _doQuery,` |
| 加入修改 | 585 | `onPressed: _doJoin,` |

然后在第 689 行（`_stopRun` 的 `}` 之后）插入方法：

```dart
  /// 点「登录」：校验非空 → 提示。
  void _doLogin() {
    if (_account.text.trim().isEmpty) {
      _snack('请先填账户');
      return;
    }
    if (_password.text.isEmpty) {
      _snack('请先填密码');
      return;
    }
    _snack('登录成功：${_account.text}');
  }
```

逐行解释：
- `void` = 不返回值
- `_doLogin` = 方法名，`_` 开头 = 只在本文件用
- `_account.text` = 输入框里的字
- `.trim()` = 去首尾空格
- `.isEmpty` = 是否为空
- `return;` = 立刻结束
- `_snack(...)` = 底部提示条（第 125 行定义）
- `${...}` = 把变量塞进字符串

### 让「发送」可点

第 484 行 `onPressed: null,`（禁用）改成：

```dart
onPressed: _running ? _doSend : null,
```

含义：运行时可点，不运行禁用。

---

## 二、加控件

### 加输入框（四步）

**1. 加控制器** — 第 55 行 `_concurrency` 下面加：

```dart
  /// 备注输入框。
  final TextEditingController _remark = TextEditingController();
```

**2. 注册释放** — 第 121 行 `_concurrency.dispose();` 下面加：

```dart
    _remark.dispose();
```

**3. 加到界面** — 第 580 行附近（「价格」那个 `LabeledField` 结束后、`SizedBox(height: m.preButtonGap)` 之前）插入：

```dart
          SizedBox(height: m.rowGap),
          LabeledField(
            label: '备注',
            controller: _remark,
            hint: '选填',
          ),
```

**4. 验证** — `flutter analyze` + `flutter test`

### 加按钮（三步）

**1. 写方法** — 第 689 行后插入：

```dart
  void _doClear() {
    _account.clear();
    _password.clear();
    _quantity.text = '1';
    _price.text = '100';
    _snack('已清空');
  }
```

**2. 加到布局** — 第 662-669 行是「开始 / 结束」那一行。在第二个 `Expanded` 之后、`],`（第 671 行）之前插入：

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

加完这一行变三个按钮，每个 `Expanded` 自动三等分。太挤就把 `width: 8` 改小。

---

## 三、改颜色和尺寸：`lib/theme.dart`

### 主色（那个绿色）

第 23 行：

```dart
  static const Color primary = Color(0xFF3AAF9F);
```

`0xFF3AAF9F` 拆开：`FF`=不透明、`3A`=红、`AF`=绿、`9F`=蓝。

改成蓝色 `0xFF2E7DD1` → 全工程 30 多处跟着变（按钮、聚焦边框、选中条、下划线、滚动条）。

### 常用尺寸

| 行号 | 常量 | 现在 | 控制什么 |
|---|---|---|---|
| 152 | `kRowHeight` | 30 | 输入框/按钮/下拉高度 |
| 155 | `kRowGap` | 7 | 行间距 |
| 161 | `kPanelWidth` | 212 | 左栏宽度 |
| 171 | `kLabelWidth` | 60 | 左标签格宽度 |
| 174 | `kRadius` | 3 | 圆角 |
| 180 | `kTitleBarHeight` | 38 | 标题条高 |
| 183 | `kHeaderHeight` | 40 | 表头高 |
| 186 | `kRowItemExtent` | 34 | 表格行高 |
| 203 | `kTabBarHeight` | 34 | Tab 栏高 |
| 445 | `kDesignWidth` | 1048 | 窗口默认宽 |
| 446 | `kDesignHeight` | 682 | 窗口默认高 |
| 453 | `kWindowTitle` | 阿萨德 | 窗口标题 |

改窗口默认大小要同时改 `windows/runner/main.cpp` 里的 `kWindowWidth` / `kWindowHeight`。

### 加新颜色（正确做法）

第 88 行附近（`AppColors` 里）加：

```dart
  /// 提示：需要注意。
  static const Color notice = Color(0xFFE8A33D);
```

第 117 行附近（`WorkColors` 里）加别名：

```dart
  static const Color notice = AppColors.notice;
```

用的时候 `color: WorkColors.notice`。**别在别处直接写 `Color(0xFF...)`。**

---

## 四、底部图标与抽屉

### 换图标

`lib/widgets/nav_bar.dart` 第 21-31 行：

```dart
enum NavDestination {
  settings('设置', Icons.settings_outlined, Icons.settings),
  profile('个人中心', Icons.person_outline, Icons.person),
  menu('菜单', Icons.menu, Icons.menu_open);
```

三个参数分别是：中文名、未选中图标、选中图标。去 fonts.google.com/icons 找新图标替换 `Icons.xxx`。

### 加第四个图标

**1.** enum 里加一行：

```dart
  help('帮助', Icons.help_outline, Icons.help),
```

**2.** `main_page.dart` 第 380 行 `_buildDrawer()` 的 `switch` 里加分支：

```dart
      NavDestination.help => const Center(child: Text('帮助内容待补')),
```

> `switch` 是穷举的：加了 enum 项不加分支，`flutter analyze` 会直接报错。这是故意的。

### 改抽屉宽度 / 速度

`theme.dart`：

| 行号 | 常量 | 现在 |
|---|---|---|
| 294 | `kDrawerWidth` | 360 |
| 300 | `kDrawerDuration` | 300ms |
| 306 | `kDrawerScrimAlpha` | 0.18 |
| 283 | `kNavButtonSize` | 26 |
| 286 | `kNavIconSize` | 16 |
| 289 | `kNavBarGap` | 6 |

速度改 `200` 更快、`450` 更慢。

### 抽屉里加设置项

`lib/widgets/drawer_panels.dart` 的 `SettingsPanel.build` 里照抄：

```dart
        CheckBoxRow(
          label: '自动更新',
          value: autoUpdate,
          onChanged: onAutoUpdateChanged,
        ),
```

然后在 `SettingsPanel` 构造函数加 `required this.autoUpdate` 和 `required this.onAutoUpdateChanged`，并在 `main_page.dart` 第 385 行传进去：

```dart
        onAutoUpdateChanged: (bool v) => setState(() => _autoUpdate = v),
```

`_autoUpdate` 字段加在第 90 行附近。

---

## 五、报错怎么办

### `RenderFlex overflowed by X pixels`

内容太高装不下。按顺序试：

**1. 收紧密排档** — `theme.dart` 第 261-276 行：

```dart
const double kDenseRowGap = 2;   // 改成 1
const double kDenseCardGap = 1;  // 已是 1
```

**2. 加第四档** — 第 355 行 `dense` 下面照抄：

```dart
  static const PanelMetrics ultraDense = PanelMetrics(
    rowGap: 1,
    cardGap: 1,
    sectionGap: 1,
    groupBoxPadding: EdgeInsets.fromLTRB(6, 1, 6, 1),
    preButtonGap: 1,
  );
```

第 364 行 `byDescendingSpace` 列表末尾加 `ultraDense`。

### `A TextEditingController was used after being disposed`

用了已销毁的输入框。检查 `await` 之后有没有 `if (!mounted) return;`。

### `setState() called after dispose()`

页面关了还在刷新。异步回调里加：

```dart
    if (!mounted) return;
    setState(() { ... });
```

### `The named parameter 'xxx' isn't defined`

组件没这个参数。去对应文件看构造函数，比如 `labeled_field.dart` 第 17-30 行。

### 点了没反应

1. 回调是不是 `() {}`（空的）？
2. 有没有包 `setState`？
3. 按钮是不是 `onPressed: null`（禁用）？

---

## 六、需求速查

| 我想… | 文件 | 行号 |
|---|---|---|
| 改卡片标题 | main_page.dart | 446/507/595/637 |
| 改输入框标签 | main_page.dart | 454/460/468/558/564/570/576/645 |
| 改按钮文字 | main_page.dart | 480/490/532/583/656/665 |
| 给按钮加逻辑 | main_page.dart | 494/534/585 |
| 加输入框 | 见第二节 | — |
| 加按钮 | 见第二节 | — |
| 改主色 | theme.dart | 23 |
| 改行高 | theme.dart | 152 |
| 改左栏宽 | theme.dart | 161 |
| 改窗口标题 | theme.dart | 453 |
| 改窗口大小 | theme.dart + main.cpp | 445/446 |
| 改 Tab 名字 | main_page.dart | 95 |
| 改表格列 | models.dart | 97/111/123 |
| 改示例数据 | models.dart | 225/280/322 |
| 加底部图标 | nav_bar.dart + main_page.dart | 21 / 380 |
| 改抽屉宽/速 | theme.dart | 294 / 300 |

---

## 七、检查清单

```
□ flutter analyze  → No issues found!
□ flutter test     → All tests passed!
□ 新 controller 有 dispose()
□ 颜色没写死在 theme.dart 之外
□ 没跑 dart format
□ 窗口拉到 880x620 试过，没黄黑警示条
```

运行：`flutter run -d windows`
打包：`flutter build windows --release` → `build\windows\x64\runner\Release\app_ui.exe`
