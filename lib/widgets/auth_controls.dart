// ---------------------------------------------------------------------------
// 通用组件（验证页那一套）—— 桶文件
//
// 这一批组件只服务于验证页（登录 / 注册 / 充值 / 协议）。工作台的控件在
// widgets/panel/ 下，两套尺寸节奏不同（44 高 vs 30 高），不要混用。
//
// 目录：
//   auth/pill_button.dart      胶囊主按钮（登录 / 注册 / 提交数据）
//   auth/field_input.dart      带前置图标的输入框 + 校验红框抖动
//   auth/check_pill.dart       方框勾选（记住密码 / 自动登录）
//   auth/link_text.dart        文字链接
//   auth/circle_buttons.dart   右上角圆形「返回 / 关闭」
//   auth/form_title.dart       表单标题
//
// 尺寸约定（参考图实测值）：
//   · 输入框高 44，图标 14，提示文字 13
//   · 按钮 160x40 胶囊形，文字 14 白色
//   · 勾选框 18x18 圆角 3
//
// 想加新组件：在 auth/ 下新建一个文件，然后在这里加一行 export。
// ---------------------------------------------------------------------------
export 'auth/check_pill.dart';
export 'auth/circle_buttons.dart';
export 'auth/field_input.dart';
export 'auth/form_title.dart';
export 'auth/link_text.dart';
export 'auth/pill_button.dart';
