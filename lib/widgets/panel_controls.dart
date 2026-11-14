// ---------------------------------------------------------------------------
// 工作台通用小组件 —— 桶文件
//
// 引用方只写一行：
//     import 'package:app_ui/widgets/panel_controls.dart';
// 就能拿到下面五个组件，不必记住每个文件的确切名字。
//
// 目录：
//   panel/section_label.dart    分区标题（登录区 / 信息区 / 选项区）
//   panel/labeled_field.dart    带左标签的输入框（[标签][输入框] 紧贴两格）
//   panel/panel_button.dart     面板按钮（发送 / 登录 / 查询 / 加入修改）
//   panel/panel_dropdown.dart   下拉选择（功能 / 方式 / 支付）
//   panel/check_box_row.dart    方框勾选（工作台后续加开关时用）
//
// 想加新组件：在 panel/ 下新建一个文件，然后在这里加一行 export。
// ---------------------------------------------------------------------------
export 'panel/check_box_row.dart';
export 'panel/labeled_field.dart';
export 'panel/panel_button.dart';
export 'panel/panel_dropdown.dart';
export 'panel/section_label.dart';
