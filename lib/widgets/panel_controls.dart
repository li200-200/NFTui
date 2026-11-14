// ---------------------------------------------------------------------------
// 工作台通用小组件 —— 桶文件
//
// 引用方只写一行：
//     import 'package:app_ui/widgets/panel_controls.dart';
// 就能拿到下面这些组件，不必记住每个文件的确切名字。
//
// 目录：
//   panel/section_label.dart    分区标题（登录区 / 信息区 / 选项区）
//   panel/labeled_field.dart    带左标签的输入框（[标签][输入框] 紧贴两格）
//   panel/bare_field.dart       无标签输入框（.ui 里独占整行的 QLineEdit）
//   panel/panel_button.dart     面板按钮（发送 / 登录 / 查询 / 加入修改）
//   panel/panel_dropdown.dart   下拉选择（功能 / 方式 / 支付 / 通知方式）
//   panel/check_box_row.dart    方框勾选（多选语义）
//   panel/switch_row.dart       开关（单个功能的开与关）
//   panel/setting_atoms.dart    设置页的说明文字（`*` 开头的提示）
//   panel_group_box.dart        卡片（左栏四张卡片与设置页五张卡片共用）
//   object_names.dart           .ui 里的 objectName 常量表
//
// 【为什么把 panel_group_box 也并进来】
// 设置页现在复用左栏的卡片样式（标题同样是左对齐的主色小标题）。早先它只被
// main_page 直接 import，设置页那边就只好自己写一个「标题压在边框上」的
// SettingGroupBox —— 两套标题样式并存正是观感不一致的来源。
//
// 想加新组件：在 panel/ 下新建一个文件，然后在这里加一行 export。
// ---------------------------------------------------------------------------
export 'object_names.dart';
export 'panel/bare_field.dart';
export 'panel/check_box_row.dart';
export 'panel/labeled_field.dart';
export 'panel/panel_button.dart';
export 'panel/panel_dropdown.dart';
export 'panel/section_label.dart';
export 'panel/setting_atoms.dart';
export 'panel/switch_row.dart';
export 'panel_group_box.dart';
