# 验证页移植说明

把 `snap_2026-10-28` 工程里的**验证页**（登录 / 注册 / 充值 / 协议）整体搬进本工程，
界面与参考工程逐像素一致，业务逻辑**全部在 C 里**，Flutter 只负责画界面。

---

## 一、两层结构

移植后本工程与参考工程同构：

```
E:\xm\UI
├── lib/                           ← Flutter：只有 UI
│   ├── pages/
│   │   ├── login_page.dart        ← 登录（启动页）
│   │   ├── register_page.dart     ← 注册
│   │   ├── recharge_page.dart     ← 充值
│   │   ├── agreement_page.dart    ← 网络协议（路由弹出）
│   │   └── main_page.dart         ← 工作台（原有）
│   ├── widgets/
│   │   ├── auth/                  ← 验证页那套控件（44 高）
│   │   │   ├── field_input.dart      带图标输入框 + 红框抖动
│   │   │   ├── pill_button.dart      160x40 胶囊主按钮
│   │   │   ├── check_pill.dart       18x18 方框勾选
│   │   │   ├── link_text.dart        文字链接
│   │   │   ├── circle_buttons.dart   右上角返回 / 关闭
│   │   │   └── form_title.dart       表单标题
│   │   ├── auth_controls.dart     ← 上面那批的桶文件
│   │   ├── auth_scaffold.dart     ← 40:60 分栏骨架 + 页脚
│   │   ├── illustration_panel.dart← 左插画 + 飘落花瓣
│   │   ├── window_chrome.dart     ← 无边框外壳 + 拖动层 + 窗口按钮
│   │   ├── form_messages.dart     ← 字段判定码 → 文案
│   │   └── panel/                 ← 工作台那套控件（30 高，原有）
│   └── theme.dart                 ← AppColors / WorkColors / AuthColors
│
└── packages/pigeon_core/          ← C：全部业务逻辑
    ├── hook/build.dart            ← native assets 构建钩子（编 C）
    ├── src/
    │   ├── pigeon_core.c/.h          导出层：拦空指针 + ABI 自检 + 收尾
    │   ├── pc_auth.c/.h              表单校验 + 登录 / 注册 / 充值
    │   ├── pc_bsphp.c/.h             BSPHP 协议（AES + RSA + 握手 + 心跳）
    │   ├── pc_http.c/.h              WinHTTP 封装
    │   ├── pc_cred.c/.h              记住密码（XOR 混淆落盘）
    │   ├── pc_authnet.c/.h           机器码（注册表 MachineGuid）
    │   ├── pc_common.c/.h            字符串 / UTF-8 工具
    │   └── pc_log.c/.h               运行日志控制台 + 崩溃处理器
    ├── lib/
    │   ├── pigeon_core.dart       ← 对外 API（页面只 import 这一个）
    │   └── src/
    │       ├── pigeon_core_native.dart  @Native 声明（part 挂载）
    │       ├── types.dart               C 结构体的 Dart 镜像
    │       └── ffi_util.dart            UTF-8 入参分配 / 释放
    └── test/pigeon_core_test.dart  ← 15 条：直接验证 C 里的规则
```

依赖方向是单向的：`app_ui → pigeon_core`。C 不知道 Flutter 的存在。

---

## 二、C 核心是怎么被编译进来的

用 **native assets**（Dart 官方机制），不是 CMake、也不是手动 `dll` 拷贝。

`packages/pigeon_core/hook/build.dart` 里声明：

```dart
final CLibrary library = CLibrary(
  name: 'pigeon_core',
  assetName: 'pigeon_core.dart',   // 资产 ID = package:pigeon_core/pigeon_core.dart
  sources: <String>[ 'src/pigeon_core.c', 'src/pc_auth.c', ... ],  // 逐文件登记
  flags: isWindows ? const <String>['/utf-8'] : const <String>[],
);
```

`flutter build windows` 时 SDK 自动跑这个 hook，`cl.exe` 编出 `pigeon_core.dll`
放进 `build/windows/x64/runner/Release/`。

### 三个容易踩的坑

**1. `assetName` 必须与 Dart 库同名。**
`@Native()` 不写 `assetId` 时，资产 ID 由**声明所在库的 URI**推导。所以
`assetName: 'pigeon_core.dart'` + 声明放在 `lib/pigeon_core.dart`（`part` 挂载，
库 URI 不变）→ 运行时才绑得上。改成 `import` 一个 `src/` 下的库会变成
`package:pigeon_core/src/...`，编译能过、运行时「Failed to lookup symbol」。

**2. 系统库要自己 `#pragma comment(lib, ...)`。**
`native_toolchain_c` 不像 CMake 那样自动链接。原工程里 `bcrypt.lib` / `crypt32.lib`
是 `pc_shide.c` 挂的，而那个文件不在移植范围内 —— 所以补在 `pc_bsphp.c` 顶部：

```c
#pragma comment(lib, "bcrypt.lib")
#pragma comment(lib, "crypt32.lib")
#pragma comment(lib, "advapi32.lib")
```

漏了会报一长串 `LNK2019: 无法解析的外部符号 BCryptOpenAlgorithmProvider`。

**3. `routing` 必须显式写 `ToAppBundle()` + `dynamic`。**
不写的话默认值随构建模式变，release 构建会因为「静态资产送去 link hook、但本包
没有 `hook/link.dart`」直接失败。

---

## 三、C 模块的移植边界

原工程的 C 有 13 个 `.c`，本工程只取**验证页依赖的闭包**：

| 保留 | 原因 |
|---|---|
| `pigeon_core.c` | 导出层，所有 `PC_API` 符号定义在这里 |
| `pc_auth.c` | 表单校验 + 三个业务接口 |
| `pc_bsphp.c` | BSPHP 协议（登录 / 注册 / 充值都走它） |
| `pc_http.c` | `pc_bsphp.c` 依赖 |
| `pc_cred.c` | 记住密码 / 自动登录 |
| `pc_authnet.c` | 机器码（BSPHP 提交参数要用） |
| `pc_common.c` | 字符串工具 |
| `pc_log.c` | 运行日志 + 崩溃处理器 |

| 未移植 | 原因 |
|---|---|
| `pc_task.c` | 任务状态机（工作台业务，本期不做） |
| `pc_engine.c` | 抢单引擎线程池 |
| `pc_shide.c` | Shide 刷单接口 |
| `pc_notify.c` | WxPusher 推送 |
| `pc_sound.c` | 抢单音效 |

**裁剪时同步改了三处**，漏一处会编译失败或运行时读错位：

1. `src/pigeon_core.h` —— 删掉 task / shide / engine / notify / sound 五个章节
   （原 255–647 行），从 681 行减到 288 行。
2. `src/pigeon_core.c` —— 删掉对应的 ABI 断言、`pc_abi_probe` 里的输出项、
   `pc_task_*` 全部实现，以及 `pc_core_shutdown` 里的 `pc_sound_shutdown()` /
   `pc_task_impl_stop()` 两行。
3. `lib/src/types.dart` —— 删掉 `PcTaskStatus` 与 task / shide / engine 的结构体镜像
   （675 行 → 231 行）；`lib/pigeon_core.dart` 同步把 `pcAbiCheck` 的比对项
   从 9 项减到 2 项。

> **以后要移植那几个模块时**：ABI 断言与 `pc_abi_probe` 的输出**顺序必须与
> Dart 侧 `pcAbiCheck` 的 `expect` 数组一一对应**（FFI 按顺序比）。原工程的
> 顺序是 `form → auth → task_row → shide_session → shide_vehicle → shide_goods
> → shide_order → engine_status → engine_account`，照这个补回去。

---

## 四、校验规则在 C 里，文案在 Dart 里

这是整套设计里最关键的分工。

### C 只回答「哪个字段出了哪类问题」

`pc_auth.c` 的 `pc_form_*` 三个函数是**唯一**一份校验规则，`validate_` 与业务接口
共用（规则不会漂移）：

```c
static int32_t pc_field_username(const pc_slice* s) {
  if (s->len == 0) return PC_FIELD_EMPTY;
  n = pc_utf8_count(s);
  if (n < PC_USER_MIN_LEN || n > PC_USER_MAX_LEN) return PC_FIELD_BAD_LENGTH;
  for (...) { if (!alnum) return PC_FIELD_BAD_CHARS; }   // 汉字天然走这里
  return PC_FIELD_OK;
}
```

阈值：用户名 6–16 位字母数字、密码 ≥6、卡密 ≥8（本地宽松预检，真实规则由服务端裁决）。

**注意「先长度后字符集」**：5 个汉字返回 `BAD_LENGTH` 而不是 `BAD_CHARS`。
写测试时要用 6 个汉字才能测到字符集那条分支。

### Dart 把码翻成文案，但本地校验失败不显示

`lib/widgets/form_messages.dart`：

```dart
String? userFieldMessage(int code) => switch (code) {
      PcField.ok => null,
      PcField.empty => '请输入用户名',
      PcField.badLength => '用户名长度必须在 6-16 位之间',
      ...
      _ => '用户名格式不正确',
    };
```

**`message != null` 才是「这个框要变红」的判据。** 所以每个非 `ok` 的码都必须有
分支 —— 否则现象是「校验没通过但界面毫无反应」，比报错更难查。

但**文案平时根本不显示**：本工程的交互约定是

- 本地校验失败 → 只红框 + 左右抖两下，**不出文字**；
- 服务端结果（账号密码不对 / 连不上）→ 才出底部错误条，文案由 C 侧给（官方提示语）。

对应的测试：`test/auth_pages_test.dart` 的「空表单点登录：不出文字，只把两个框标红」。

### 抖动为什么需要 `errorTick`

`FieldInput` 的抖动由两个条件触发：

```dart
final bool justErrored = widget.hasError && !oldWidget.hasError;   // 第一次失败
final bool reSubmitted = widget.hasError && widget.errorTick != oldWidget.errorTick;  // 没改又点了一次
```

只有第一个条件的话，「内容没改就连点两次提交」第二次毫无反馈（`hasError` 恒为
true）。所以页面每次提交都 `_tick++`。

---

## 五、两套配色，不要合并

`theme.dart` 里现在有三个类：

| 类 | 用途 | 输入框底 | 边框 |
|---|---|---|---|
| `AppColors` | 全局色板 | `#FFFFFF`（工作台） | `#D8DBDE` |
| `WorkColors` | 工作台别名，全部指向 `AppColors` | 同上 | 同上 |
| `AuthColors` | **验证页专用** | `#F3F3F5` 灰 | `#E4E4E8` 浅 |

两套的来源不同：验证页色值从登录参考图逐像素统计（灰底输入框、浅边框、偏亮的
三级文字 `#9A9A9A` / `#B0B0B0`）；工作台从 Win32 工具界面改色（白底输入框、深边框）。

硬合成一套必然要把其中一边改掉，所以各留各的。**同值的项直接引用 `AppColors`**
（`AuthColors.primary = AppColors.primary`），只有真正不同的才在 `AuthColors` 里写死。

---

## 六、两个窗口尺寸

| 界面 | 尺寸 | 来源 |
|---|---|---|
| 验证页 | **800 x 550** | 参考图逐像素校对（输入框 44 高、表单列 280、左右 40:60） |
| 工作台 | **1048 x 682** | `untitled.ui` 的 geometry |

三处必须一致：

1. `windows/runner/main.cpp` 的 `kWindowWidth/kWindowHeight` —— **启动时是 800x550**
   （应用启动页是登录页，反过来会出现「先闪一个大窗再跳成小窗」）；
2. `lib/theme.dart` 的 `kAuthWidth/kAuthHeight` 与 `kDesignWidth/kDesignHeight`；
3. `lib/main.dart` 的 `WindowOptions`。

登录成功时由 `_enterWorkPage` 切尺寸，**顺序很关键**：

```dart
await windowManager.setMaximumSize(const Size(kDesignWidth, kDesignHeight));  // 先放开上限
await windowManager.setMinimumSize(const Size(kDesignWidth, kDesignHeight));
await windowManager.setSize(const Size(kDesignWidth, kDesignHeight));
```

启动时锁的是 `minimum == maximum == 800x550`，直接 `setSize(1048x682)` 会被上限夹住 ——
窗口停在 800x550 而界面按 1048 布局，右下角直接被裁掉。

`_backToLogin` 对称，顺序反过来（先放开下限）。

---

## 七、页面切换与登录态

`lib/main.dart` 的 `AppPage` 枚举：

```dart
enum AppPage { login, register, recharge, work }
```

- `login` 是启动页，`work` 只能由登录成功到达 —— 绕不过验证；
- 切页面用 `AnimatedSwitcher` + `KeyedSubtree(ValueKey<AppPage>)`，200ms 淡入淡出；
- 验证页装在 `WindowShell` 里（无边框 + 拖动层），工作台自带 `WorkTitleBar`。

账号传递：`_userName` 由 `_enterWorkPage` 收到，传给 `MainPage(loginAccount:)`，
后者在 `initState` 里**预填**进「登录区」的账户框。

> 在 `initState` 填而不是 `build`：`build` 每次 `setState` 都跑，在里面写
> `controller.text` 会把用户后来的修改反复覆盖掉 —— 表现是「改了账号，一刷新又变回
> 登录时那个」。

「退出登录」通过 `MainPage(onLogout:)` 回到 `_backToLogin`，同时把窗口收回 800x550。

---

## 八、记住密码 / 自动登录

持久化在 C 里（`pc_cred.c`），密码做一层 XOR 混淆落盘 —— 不是真加密，
「记住密码」本身就是可逆约定，只求「别让密码明文躺在一个 .txt 里」。

```dart
final String _credPath = widget.credPath ?? pcCredDefaultPath();
// 空串 = 持久化完全禁用（测试用这个隔离真实账号文件）
```

约定：

- 文件不存在 / 损坏 → `remember=0`、空表单，`load` 仍返回成功（调用方不需要区分
  「没记住过」和「读坏了」）；
- 取消勾选「记住密码」→ **立刻**清盘，不等下次登录成功才覆盖；
- 勾上「自动登录」→ 强制勾上「记住密码」（依赖关系）；
- 自动登录每次启动只试一次（`_autoLoginTried`），失败时 `_cancelAutoLogin()`
  **把标志写回磁盘**（不只改内存），下次启动不再重试，但用户名密码仍填着。

---

## 八点五、登录成功后的三件事：日志控制台 / 心跳 / 公告

登录成功（`_enterWorkPage`）之后按这个顺序做四件事，顺序是有讲究的：

```dart
Future<void> _enterWorkPage(String user) async {
  pcLogInit();      // 1) 分配日志控制台（不可关闭）
  pcAbiCheck();     // 2) 结构体布局自检，结论写进日志
  unawaited(pcAuthNoticeAsync().catchError(...));  // 3) 拉系统公告（后台，不 await）
  setState(...);    // 4) 切页面 + 改窗口尺寸
}
```

### 1. 日志控制台（`pcLogInit`）

C 侧 `AllocConsole()` 分配一个独立控制台，`freopen` 把 stdout/stderr 指过去，
标题设成「鸽鸽软件助手 - 运行日志」，并删掉系统菜单里的关闭项（右上角 X 变灰）。

**它必须在最前面**：后面几步（ABI 自检、公告、心跳）都要往日志里写，
控制台没建好那些行就丢了。

几个细节（都在 `pc_log.c` 里）：

- **关掉「快速编辑」模式**。默认开启时，用户在日志窗口里拖选文字会让 conhost
  阻塞所有写入 —— 第一个写日志的线程卡在 `fwrite` 里不放锁，其余线程全排队，
  整个程序看起来像卡死。
- **`AllocConsole` 失败就降级写 `pigeon.log`**（exe 目录，追加）。两条路都失败
  才彻底静默。
- **一行日志一次 `fputs`**，不是分三次 printf。分三次时并发打日志会互相穿插成
  `[12:00:00] >>>>>>>>>>[12:00:00] >>>>>>>>>>...`。

### 2. ABI 自检（`pcAbiCheck`）

比对 C 实际编译出来的结构体尺寸与 Dart 镜像。不一致不会编译报错，只会表现成
「读出来的字符串后面粘着别的字段」—— 启动时对一次，几十微秒，把隐性不一致
变成日志里一条明确结论。

### 3. 系统公告（`pcAuthNoticeAsync`）

`api_type "1"` 的公告接口，C 侧逐条输出到运行日志。

**必须是 fire-and-forget（不 await）**：它是一次真实网络请求（最长 25s），
同步等它会把窗口卡在验证页上。

**必须挂 `catchError`**：这是个没有 await 的 Future，若公告接口异常（断网 /
服务端返回异常），未处理的异步错误会冒到 Zone —— debug 下直接变成红屏报错，
release 下则静默丢失，排查时看不到任何线索。

### 4. 心跳（`pcHeartbeatStart`）

**不在 `_enterWorkPage` 里开，而是在 `MainPage.initState` 里开** —— 这是与
snap 一致的划法，理由是「页面存活期 == 心跳存活期」：

```dart
// main_page.dart
void initState() {
  ...
  final int hbRc = pcHeartbeatStart();
  pcLog(hbRc == PcStatus.ok ? '[心跳] 已开启...' : '[心跳] 启动失败 rc=$hbRc');
}

void dispose() {
  pcHeartbeatStop();
  pcLog('[心跳] 已请求停止（离开工作台）');
  ...
}
```

这样「退出登录 → 回验证页」会自然停掉心跳，不需要在 `_backToLogin` 里再补一次。
窗口关闭那条路径由 `main.dart` 的 `onWindowClose` 兜底（它也先 `pcHeartbeatStop`
再 `pcCoreShutdown`）。

心跳本身（`pc_bsphp.c` 的 `hb_loop`）：

- 每 **10 分钟**调一次 `timeout.lg` 保活，用登录 / 注册 / 充值响应里带回来的会话串；
- **三级分类处理**：`PC_HB_OK` → 静默进下一轮；`PC_HB_TRANSIENT` → 先重握手自愈
  再判，仍不行只记一条日志；`PC_HB_FATAL` → 走 `pc_core_shutdown` 收尾退出；
- **`start` 幂等**：已在跑时复用现有线程，不叠加。这条很重要 ——「退出登录再登录」
  会来回调 start，若不幂等就会攒出多条心跳线程，双倍消耗服务端在线名额
  （5048/5049/5050「在线数超限」会因此提前引爆）；
- **`stop` 是协作式**：置标志 + 唤醒等待中的线程，调用立即返回，不等 join
  （线程可能卡在最长 25s 的网络请求里）。要确认真收干净就轮询
  `pcHeartbeatIsRunning`。

> **为什么 Dart 侧还要自己写一条「已开启」日志**
> C 侧对心跳成功是**静默**的（否则每 10 分钟一条「一切正常」会把日志刷满），
> 那样用户在日志里就看不到「心跳到底起没起」。所以启动那一刻补一条，把返回码
> 也记下来；之后的心跳成败仍由 C 侧按需记录（只在暂时失败 / 授权失效时写）。

### 实机日志长这样

```
[00:32:33] >>>>>>>>>>ABI 自检通过（2 项）
[00:32:33] >>>>>>>>>>[心跳] 已开启（每 10 分钟一次 timeout.lg 保活；成功时不写日志，只在失败 / 授权失效时记录）
[00:32:34] >>>>>>>>>>========== 系统公告 ==========
[00:32:34] >>>>>>>>>>测试项目请勿破解！没有车辆不会抢。可以使用地址刷。软件没有防挤号功能，请勿再去登录
[00:32:34] >>>>>>>>>>============================================
```

> **自动化验证时的坑**：日志控制台是一个**真实窗口**，出现后可能盖在验证页的
> 登录按钮上，导致屏幕坐标点击落空。自动化里要么先找到控制台窗口（`app_ui`
> 进程下类名为 `C` 的可见窗口）并移开，要么直接用 `SendInput`/真实鼠标事件点
> 登录按钮 —— `PostMessage` 的点击不进 Flutter 的手势竞技场，对按钮无效。

---

## 九、验证方式

### 静态

```powershell
flutter analyze                       # 必须 No issues found!
flutter test                          # UI：95 条
cd packages\pigeon_core
flutter analyze                       # 核心包也要干净
flutter test                          # C 核心：19 条（会真的编译 C）
```

### 测试分工

| 文件 | 条数 | 盯什么 |
|---|---|---|
| `packages/pigeon_core/test/pigeon_core_test.dart` | 19 | **C 里的规则**：逐条核对校验判定码、ABI 尺寸、凭据读写、心跳启停 |
| `test/auth_pages_test.dart` | 15 | 验证页几何：40:60 分栏、表单列 280、输入框 44、按钮 160x40 胶囊、红框不出文字 |
| `test/auth_navigation_test.dart` | 5 | 页面切换回调：注册 / 充值 / 返回 / 协议页弹出 |
| `test/auth_workbench_bridge_test.dart` | 6 | 账号预填、退出登录接线、**心跳随工作台启停** |
| 其余 7 个文件 | 69 | 工作台（原有，未受影响） |

> **为什么 C 规则要在 Dart 侧测**：`pcAuthValidateLogin` 走 FFI 调进 C。若 FFI 绑错
> 函数（符号名相近、参数顺序颠倒），调用照样返回、异常照样不抛，只是结论悄悄错了。
> 所以那 19 条断言的是**具体判定码 / 具体状态**，不是「不抛异常」。

> **心跳测试为什么必须用 `tester.runAsync`**
> `testWidgets` 默认跑在 `FakeAsync` 里：`Future.delayed` 不会真的等，时间由
> `tester.pump` 手动推进；而 C 侧心跳是**真实 OS 线程**，退出只跟真实时间有关。
> 在 FakeAsync 里轮询 `pcHeartbeatIsRunning` 会永远看到旧值直到测试超时 ——
> `runAsync` 把那段代码放回真实事件循环，两边才对得上。
>
> 另外测试环境没有真实会话，心跳会走「TRANSIENT → 重新握手」分支（2 个网络
> 请求，每个都可能等到连接超时），所以等待上限给到 30 秒。真正的 bug 是
> running 永远不归零，那样 30 秒也过不了 —— 放宽上限不会掩盖问题。

### 实机

```powershell
flutter build windows --release
.\build\windows\x64\runner\Release\app_ui.exe
```

已确认：

- 窗口精确 800x550，登录页渲染与参考图一致（左插画 40% + 右表单 60%、灰底输入框、
  页脚右下角）；
- **`pigeon_core.dll`（241 KB）打进 Release 包**，导出符号齐全
  （`pc_auth_validate_login` / `pc_cred_load` / `pc_abi_probe` 等）；
- **`pcCredLoad` 在真实程序里读出了保存的账号密码并预填** —— 整条 FFI 链路实机跑通；
- **点登录 → C 侧网络登录成功 → 窗口自动切到 1048x682 → 工作台正常渲染**；
- **登录后日志控制台出现**，标题「鸽鸽软件助手 - 运行日志」，内容依次是
  `ABI 自检通过（2 项）` → `[心跳] 已开启…` → `系统公告`（服务端真实返回的正文）。

> 屏幕坐标点击在自动化里不可靠（窗口被遮挡、`SendInput` 被 UIPI 拦、`PostMessage`
> 的点击不进 Flutter 的手势竞技场）。交互正确性用 widget 测试覆盖，实机只用于
> 看「长得对不对」。另外日志控制台本身是个真实窗口，出现后会盖住验证页，
> 自动化点登录前要先把它移开。

---

## 十、加新 C 接口要动的地方

五处，缺一处会以「符号找不到 / 链接期未定义」暴露：

1. `src/pigeon_core.h` —— 声明导出函数（`PC_API`）
2. `src/*.c` —— 实现
3. `hook/build.dart` 的 `sources` —— 新 `.c` 文件必须登记
4. `lib/src/pigeon_core_native.dart` —— 加 `@Native` 声明
5. `lib/pigeon_core.dart` —— 加面向界面的封装（UTF-8 分配 + 内存释放）

新增**结构体**还要同步 `lib/src/types.dart` 的镜像，并在 `pigeon_core.c` 里加
`PC_ABI_MSG_CHECK` 断言、在 `pc_abi_probe` 末尾追加输出项、在 `pcAbiCheck` 的
`expect` 数组按同样顺序追加。

---

## 十一、与参考工程的差异

| 项 | 参考工程 | 本工程 | 原因 |
|---|---|---|---|
| C 模块 | 13 个 `.c` | 8 个（验证页闭包） | 工作台业务本期不做 |
| `pcAbiCheck` 比对项 | 9 项 | 2 项 | 对应上一条 |
| 配色类 | `AppColors` + `WorkColors` | `AppColors` + `WorkColors` + `AuthColors` | 工作台色值先落地，验证页需独立一套 |
| 窗口尺寸常量 | `kDesignWidth=800`（验证页） | `kAuthWidth=800` + `kDesignWidth=1048` | 两个界面尺寸不同，不能共用一个名字 |
| 工作台页面 | `work_page.dart` | `main_page.dart`（原有，`untitled.ui` 还原） | 本工程工作台按 `.ui` 重绘过 |

验证页的**视觉**（尺寸、比例、颜色、动效时长、文案）与参考工程完全一致；
上面这些差异都在「非视觉」层面。
