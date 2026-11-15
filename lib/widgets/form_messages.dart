// ---------------------------------------------------------------------------
// 字段判定码 → 提示文字。
//
// 【为什么文案不放在 C 里】
// 本项目的交互约定是「本地校验失败只让输入框变红、抖两下，不出任何文字」，
// 只有服务端结果才出提示条。也就是说这些字符串平时根本不显示 —— 它们属于
// 表现层，C 核心只负责判定「哪个字段出了哪类问题」。
//
// 【但返回 null 仍然是有意义的】
// 页面用 `message != null` 决定这个输入框要不要变红。所以 C 新加一个字段码时，
// 这里必须同步加一条分支，否则现象是「校验没通过但界面毫无反应」——
// 比报错更难查。
//
// 放在一个文件里而不是三个页面各写一遍：三个页面的「用户名 / 密码 / 卡密」
// 文案必须完全一致，分散写迟早会漂移。
//
// 槽位划分（不再复用）：`pwd2` 专指注册页的「确认密码」，`pwdAcc` 专指充值页
// 的「账号密码」。这样两个页面各看各的槽位，不会因为「同一个槽位被两页塞了
// 不同含义」而对不上号。
//
// 【每个函数都必须先把 PcField.ok 判成 null】
// 页面靠 `message != null` 决定要不要变红。若用 `_ => null` 兜底，C 侧新增
// 字段码时界面会「校验没过却毫无反应」；所以这里反过来 —— ok 才返回 null，
// 其余非零码一律给出文字。
// ---------------------------------------------------------------------------
import 'package:pigeon_core/pigeon_core.dart';

/// 用户名。三个页面共用。
///
/// 阈值取自服务端要求（错误码 -82002：6-16 位字母或数字）；充值页不做
/// 用户名长度校验，走不到 [PcField.badLength]。
String? userFieldMessage(int code) => switch (code) {
      PcField.ok => null,
      PcField.empty => '请输入用户名',
      PcField.badLength => '用户名长度必须在 6-16 位之间',
      PcField.badChars => '用户名只能包含字母和数字',
      PcField.tooShort => '用户名长度不够',
      PcField.tooLong => '用户名长度超出上限',
      _ => '用户名格式不正确',
    };

/// 密码 / 充值页的「账号密码」（两者规则一致，共用这套文案）。
String? passwordFieldMessage(int code) => switch (code) {
      PcField.ok => null,
      PcField.empty => '请输入密码',
      PcField.tooShort => '密码至少 6 位',
      PcField.tooLong => '密码长度超出上限',
      _ => '密码格式不正确',
    };

/// 注册页的「确认密码」。
String? passwordConfirmMessage(int code) => switch (code) {
      PcField.ok => null,
      PcField.empty => '请再次输入密码',
      PcField.mismatch => '两次输入的密码不一致',
      _ => '确认密码格式不正确',
    };

/// 卡密。
///
/// 「至少 8 位」是本地的宽松预检，不是服务端的规则 —— 官方对充值卡密的要求
/// 是恰好 16 位，但那条规则由服务端用 -84001 告知更准确，界面上会原样显示
/// 官方提示语。这里只拦明显无效的输入，省一次网络往返。
String? cardFieldMessage(int code) => switch (code) {
      PcField.ok => null,
      PcField.empty => '请输入卡密',
      PcField.badCard => '卡密格式不正确，至少 8 位',
      PcField.tooLong => '卡密长度超出上限',
      _ => '卡密格式不正确',
    };
