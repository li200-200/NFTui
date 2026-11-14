// ---------------------------------------------------------------------------
// .ui 里的 objectName —— 全工程的唯一来源
//
// 【为什么需要这个文件】
// 需求是「所有组件的 objectName 改为 ui 的 objectName」。散着改只能保证「看起来
// 差不多」，一旦 .ui 再次重命名（这份文件已经改过三轮：label_3 → label_xhts、
// groupBox_3 → groupBox_shq、checkBox_qyxh_3 → pushButton_shqdk），Flutter 侧
// 就会悄悄跟丢。
//
// 所以把 objectName 收成常量，两个用途：
//   · 控件挂 `key: const ValueKey(kLineEditZh)` —— 测试用 byKey 精确定位，不依赖
//     文案（文案会改，objectName 是契约）；
//   · 状态字段名用同一套词的驼峰形式（_lineEditZh），从 Dart 反查 .ui 不用猜。
//
// 【命名分组与 .ui 一致】
//   untitled.ui —— 主窗口：三个 Tab、三张表、登录区 / 信息区 / 选项区 / 操作
//   config.ui   —— 设置抽屉：小号区 / 滑块区 / 上号器区 / 代理区 / 通知区
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 主窗口（untitled.ui）
// ---------------------------------------------------------------------------

/// `tabWidget_gongzuoqu` —— 右侧工作区的标签容器。
const String kTabWidgetGongzuoqu = 'tabWidget_gongzuoqu';

/// `tab_yx` / `tab_ddxx` / `tab_wc` —— 三个标签页。
const String kTabYx = 'tab_yx';
const String kTabDdxx = 'tab_ddxx';
const String kTabWc = 'tab_wc';

/// `tableWidget_yx` / `tableWidget_ddxx` / `tableWidget_wc` —— 三张表。
const String kTableWidgetYx = 'tableWidget_yx';
const String kTableWidgetDdxx = 'tableWidget_ddxx';
const String kTableWidgetWc = 'tableWidget_wc';

/// `groupBox_login` —— 左栏「登录区」。
const String kGroupBoxLogin = 'groupBox_login';

/// 登录区：`label_zh`/`lineEdit_zh`（账户）、`label_mm`/`lineEdit_mm`（密码）、
/// `label_zfmm`/`lineEdit_zfmm`（支付密码）。
const String kLabelZh = 'label_zh';
const String kLineEditZh = 'lineEdit_zh';
const String kLabelMm = 'label_mm';
const String kLineEditMm = 'lineEdit_mm';
const String kLabelZfmm = 'label_zfmm';
const String kLineEditZfmm = 'lineEdit_zfmm';

/// 登录区的两个按钮：`pushButton_fs`（发送）、`pushButton_dl`（登录）。
const String kPushButtonFs = 'pushButton_fs';
const String kPushButtonDl = 'pushButton_dl';

/// `groupBox_xx` —— 左栏「信息区」。
const String kGroupBoxXx = 'groupBox_xx';

/// 信息区：`comboBox_xx`（账号下拉）、`lineEdit_cpxx_2`（key）、
/// `label_cpxx`/`lineEdit_cpxx`、`label_cpid`/`lineEdit_cpid`、
/// `label_sl`/`lineEdit_sl`、`label_jg`/`lineEdit_jg`。
const String kComboBoxXx = 'comboBox_xx';
const String kLineEditCpxx2 = 'lineEdit_cpxx_2';
const String kLabelCpxx = 'label_cpxx';
const String kLineEditCpxx = 'lineEdit_cpxx';
const String kLabelCpid = 'label_cpid';
const String kLineEditCpid = 'lineEdit_cpid';
const String kLabelSl = 'label_sl';
const String kLineEditSl = 'lineEdit_sl';
const String kLabelJg = 'label_jg';
const String kLineEditJg = 'lineEdit_jg';

/// 信息区右侧的两个按钮：`pushButton_cx`（查询）、`pushButton_jr`（加入修改）。
const String kPushButtonCx = 'pushButton_cx';
const String kPushButtonJr = 'pushButton_jr';

/// `groupBox_xxq` —— 左栏「选项区」。
const String kGroupBoxXxq = 'groupBox_xxq';

/// 选项区的三行：`label_gn`/`comboBox_gn`、`label_fs`/`comboBox_fs`、
/// `label_zf`/`comboBox_zf`。
const String kLabelGn = 'label_gn';
const String kComboBoxGn = 'comboBox_gn';
const String kLabelFs = 'label_fs';
const String kComboBoxFs = 'comboBox_fs';
const String kLabelZf = 'label_zf';
const String kComboBoxZf = 'comboBox_zf';

/// `groupBox` —— 左栏「操作」区。
///
/// 【与设置抽屉的「通知区」同名，这是 .ui 里的真实情况】
/// untitled.ui 的「操作」区叫 `groupBox`，config.ui 的「通知区」也叫 `groupBox`。
/// 两者分属不同文件，在 Qt 里不冲突，所以这里照实保留同名 —— 改成别的就等于又
/// 造了一个 .ui 里不存在的名字，反而违背需求。
///
/// 代价：左栏可见 + 设置抽屉打开时，`byKey(const ValueKey('groupBox'))` 会命中
/// 两个。测试里用 `find.descendant` 限定在左栏或抽屉内即可。
const String kGroupBox = 'groupBox';

/// 操作区：`label_bf`/`lineEdit_bf`（并发）、`pushButton_ks`/`pushButton_js`。
const String kLabelBf = 'label_bf';
const String kLineEditBf = 'lineEdit_bf';
const String kPushButtonKs = 'pushButton_ks';
const String kPushButtonJs = 'pushButton_js';

// ---------------------------------------------------------------------------
// 设置抽屉（config.ui）
// ---------------------------------------------------------------------------

/// `groupBox_xhq` —— 小号区。
const String kGroupBoxXhq = 'groupBox_xhq';
const String kTableWidgetXh = 'tableWidget_xh';
const String kCheckBoxQyxh = 'checkBox_qyxh';
const String kPushButtonXhhq = 'pushButton_xhhq';
const String kLabelXhts = 'label_xhts';

/// `groupBox_hkq` —— 滑块区。
const String kGroupBoxHkq = 'groupBox_hkq';
const String kLabelHkts = 'label_hkts';
const String kPushButtonHklj = 'pushButton_hklj';
const String kCheckBoxQyhk = 'checkBox_qyhk';

/// `groupBox_shq` —— 上号器区。
const String kGroupBoxShq = 'groupBox_shq';
const String kLabelQz = 'label_qz';
const String kLineEditShqz = 'lineEdit_shqz';
const String kPushButtonShqlj = 'pushButton_shqlj';
const String kPushButtonShqdk = 'pushButton_shqdk';

/// `groupBox_4` —— 代理区。
const String kGroupBoxDl = 'groupBox_4';
const String kLabelDl = 'label_dl';
const String kPushButtonDllj = 'pushButton_dllj';
const String kCheckBoxQydl = 'checkBox_qydl';

/// `groupBox` —— 通知区（与左栏「操作」区同名，见 [kGroupBox] 的说明）。
const String kGroupBoxTz = kGroupBox;
const String kComboBoxTzxx = 'comboBox_tzxx';
const String kLineEditTz = 'lineEdit_tz';
const String kPushButtonDllj2 = 'pushButton_dllj_2';
const String kCheckBoxQydl2 = 'checkBox_qydl_2';
