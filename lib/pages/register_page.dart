// ---------------------------------------------------------------------------
// 注册页
//
// 对照参考图 注册.PNG：
//   右上角「返回 + 关闭」同一排
//   标题「创建账号」
//   两行说明「输入用户名,密码,卡密,」/「创建一个账户。」
//   用户名 / 密码 / 确认密码 / 卡密 四个输入框
//   胶囊按钮「注册」
//
// 注意：本页没有「阅读网络协议」勾选框。
// 协议入口统一由页脚的「软件使用协议」负责，点进去是协议正文页。
//
// 校验反馈：不弹文字，出错的输入框「边框变红 + 左右抖两下」。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/auth_scaffold.dart';
import 'package:app_ui/widgets/auth_controls.dart';
import 'package:app_ui/widgets/form_messages.dart';
import 'package:pigeon_core/pigeon_core.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({
    super.key,
    required this.onBack,
    required this.onRegisterSuccess,
  });

  final VoidCallback onBack;

  /// 注册成功，参数是用户名
  final ValueChanged<String> onRegisterSuccess;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pwd = TextEditingController();
  final TextEditingController _pwd2 = TextEditingController();
  final TextEditingController _card = TextEditingController();

  bool _obscure = true;
  bool _obscure2 = true;
  bool _loading = false;

  /// 每次点提交自增，交给 FieldInput 用来重新触发抖动
  int _tick = 0;

  String? _userError;
  String? _pwdError;
  String? _pwd2Error;
  String? _cardError;

  /// 只有服务端结果（比如用户名被占用）才出文字
  String? _globalError;

  @override
  void dispose() {
    _user.dispose();
    _pwd.dispose();
    _pwd2.dispose();
    _card.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;

    // ---- 第一段：四个字段的校验（同步，不碰网络） ----
    final PcFormResult form = pcAuthValidateRegister(
      user: _user.text,
      pwd: _pwd.text,
      pwd2: _pwd2.text,
      card: _card.text,
    );
    if (!form.formOk) {
      _tick++;
      setState(() {
        _userError = userFieldMessage(form.user);
        _pwdError = passwordFieldMessage(form.pwd);
        _pwd2Error = passwordConfirmMessage(form.pwd2);
        _cardError = cardFieldMessage(form.card);
        _globalError = null;
      });
      return;
    }

    // ---- 第二段：提交给服务端 ----
    setState(() {
      _loading = true;
      _globalError = null;
    });

    /* 同 login_page：isolate / FFI 抛错时必须把 _loading 收回来，
     * 否则按钮永久卡在「提交中」。 */
    PcAuthResult result;
    try {
      result = await pcAuthRegister(
        user: _user.text,
        pwd: _pwd.text,
        pwd2: _pwd2.text,
        card: _card.text,
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _globalError = '注册请求异常：$e';
      });
      return;
    }
    if (!mounted) return;

    // 防御性分支：第二段内部会再校验一次（规则只有一份），理论上走不到这里。
    if (result.status == PcStatus.form) {
      _tick++;
      setState(() {
        _loading = false;
        _userError = userFieldMessage(result.form.user);
        _pwdError = passwordFieldMessage(result.form.pwd);
        _pwd2Error = passwordConfirmMessage(result.form.pwd2);
        _cardError = cardFieldMessage(result.form.card);
        _globalError = null;
      });
      return;
    }

    if (result.status == PcStatus.ok) {
      setState(() => _loading = false);
      widget.onRegisterSuccess(_user.text.trim());
      return;
    }

    // 服务端拒绝（用户名已存在 -82005、卡密问题、已开启卡密注册…）
    // 或连不上服务器。文案是 C 侧翻译好的官方提示语。
    //
    // 「用户名已存在」不再单独分支：本地不判定用户名占用，服务端返回什么
    // 就显示什么 —— 官方那句「用户名已存在」比我们自己编的更准确。
    setState(() {
      _loading = false;
      _globalError = result.message.isEmpty ? '注册失败，请稍后重试' : result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      // 右上角返回按钮由骨架统一摆放，与关闭按钮同一排
      onBack: widget.onBack,
      children: <Widget>[
        const FormTitle(
          title: '创建账号',
          // 参考图里说明是两行，第二行单独成句
          subtitle: '输入用户名,密码,卡密,\n创建一个账户。',
        ),
        // 本页纵向要放 4 个输入框，比登录/充值更挤。
        // 窗口 800x550 下必须收紧，否则整体会被挤出可视区。
        const SizedBox(height: 11),

        FieldInput(
          controller: _user,
          hint: '用户名',
          icon: Icons.person_outline,
          hasError: _userError != null,
          errorTick: _tick,
          onChanged: (_) => _clear('user'),
        ),

        const SizedBox(height: 11),

        FieldInput(
          controller: _pwd,
          hint: '密码',
          icon: Icons.lock_outline,
          obscure: _obscure,
          hasError: _pwdError != null,
          errorTick: _tick,
          onChanged: (_) => _clear('pwd'),
          trailing: _MiniEye(
            obscured: _obscure,
            onTap: () => setState(() => _obscure = !_obscure),
          ),
        ),

        const SizedBox(height: 11),

        FieldInput(
          controller: _pwd2,
          hint: '确认密码',
          icon: Icons.lock_outline,
          obscure: _obscure2,
          hasError: _pwd2Error != null,
          errorTick: _tick,
          onChanged: (_) => _clear('pwd2'),
          trailing: _MiniEye(
            obscured: _obscure2,
            onTap: () => setState(() => _obscure2 = !_obscure2),
          ),
        ),

        const SizedBox(height: 16),

        // 卡密：图标用参考图里那个「卡片+密码」样式，以 Icons.pin_outlined 近似
        FieldInput(
          controller: _card,
          hint: '卡密',
          icon: Icons.pin_outlined,
          hasError: _cardError != null,
          errorTick: _tick,
          onChanged: (_) => _clear('card'),
        ),

        // 只有服务端结果才出文字提示
        if (_globalError != null) ...<Widget>[
          const SizedBox(height: 12),
          _ErrorBanner(message: _globalError!),
        ],

        const SizedBox(height: 20),

        Center(
          child: PillButton(
            label: '注册',
            loading: _loading,
            onPressed: _submit,
          ),
        ),
      ],
    );
  }

  /// 用户一动手改就把红框收掉，不用等到下次提交才判定通过。
  void _clear(String which) {
    final bool dirty = switch (which) {
      'user' => _userError != null,
      'pwd' => _pwdError != null,
      'pwd2' => _pwd2Error != null,
      _ => _cardError != null || _globalError != null,
    };
    if (!dirty) return;

    setState(() {
      if (which == 'user') _userError = null;
      if (which == 'pwd') _pwdError = null;
      if (which == 'pwd2') _pwd2Error = null;
      if (which == 'card') _cardError = null;
      _globalError = null;
    });
  }
}

// ---------------------------------------------------------------------------

class _MiniEye extends StatefulWidget {
  const _MiniEye({required this.obscured, required this.onTap});

  final bool obscured;
  final VoidCallback onTap;

  @override
  State<_MiniEye> createState() => _MiniEyeState();
}

class _MiniEyeState extends State<_MiniEye> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Icon(
          widget.obscured
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          size: 15,
          color: _hover ? AuthColors.primary : AuthColors.textMuted,
        ),
      ),
    );
  }
}

/// 服务端结果的提示条。本地空输入不走这里，一律用红框 + 抖动。
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AuthColors.error.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: AuthColors.error.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.info_outline, size: 13, color: AuthColors.error),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 11.5,
                color: AuthColors.error,
                fontFamily: kFontFamily,
                fontFamilyFallback: kFontFallback,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
