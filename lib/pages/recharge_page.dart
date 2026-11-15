// ---------------------------------------------------------------------------
// 充值页
//
// 对照参考图 充值.PNG：
//   右上角「返回 + 关闭」同一排
//   标题「充值」
//   说明「充值您的账户余额」
//   用户名 / 密码 / 卡密 三个输入框
//   胶囊按钮「提交数据」
//
// 校验反馈：不弹文字，出错的输入框「边框变红 + 左右抖两下」。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/auth_scaffold.dart';
import 'package:app_ui/widgets/auth_controls.dart';
import 'package:app_ui/widgets/form_messages.dart';
import 'package:pigeon_core/pigeon_core.dart';

class RechargePage extends StatefulWidget {
  const RechargePage({
    super.key,
    required this.onBack,
    this.initialUser = '',
    this.onSubmitSuccess,
  });

  final VoidCallback onBack;

  /// 从登录页带过来的用户名，省得用户再输一遍
  final String initialUser;

  final ValueChanged<String>? onSubmitSuccess;

  @override
  State<RechargePage> createState() => _RechargePageState();
}

class _RechargePageState extends State<RechargePage> {
  late final TextEditingController _user;
  final TextEditingController _pwd = TextEditingController();
  final TextEditingController _card = TextEditingController();

  bool _loading = false;
  bool _done = false;

  /// 每次点提交自增，交给 FieldInput 用来重新触发抖动
  int _tick = 0;

  String? _userError;
  String? _pwdError;
  String? _cardError;

  /// 服务端结果才出文字（卡密不存在、已过期…），本地校验一律只红框抖动。
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _user = TextEditingController(text: widget.initialUser);
  }

  @override
  void dispose() {
    _user.dispose();
    _pwd.dispose();
    _card.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;

    // ---- 第一段：三项校验（同步，不碰网络） ----
    final PcFormResult form = pcAuthValidateRecharge(
      user: _user.text,
      confirm: _pwd.text,
      card: _card.text,
    );
    if (!form.formOk) {
      _tick++;
      setState(() {
        _userError = userFieldMessage(form.user);
        _pwdError = passwordFieldMessage(form.pwdAcc);
        _cardError = cardFieldMessage(form.card);
      });
      return;
    }

    // ---- 第二段：提交给服务端 ----
    setState(() {
      _loading = true;
      _done = false;
      _errorMessage = null;
    });

    /* 同 login_page：isolate / FFI 抛错时必须把 _loading 收回来。 */
    PcAuthResult result;
    try {
      result = await pcAuthRecharge(
        user: _user.text,
        confirm: _pwd.text,
        card: _card.text,
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = '充值请求异常：$e';
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
        _pwdError = passwordFieldMessage(result.form.pwdAcc);
        _cardError = cardFieldMessage(result.form.card);
      });
      return;
    }

    // 服务端拒绝（-84002 卡密不存在、-84003 已被使用…）或连不上服务器。
    if (result.status != PcStatus.ok) {
      setState(() {
        _loading = false;
        _errorMessage =
            result.message.isEmpty ? '充值失败，请稍后重试' : result.message;
      });
      return;
    }

    setState(() {
      _loading = false;
      _done = true;
    });

    widget.onSubmitSuccess?.call(_user.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      // 右上角返回按钮由骨架统一摆放，与关闭按钮同一排
      onBack: widget.onBack,
      children: <Widget>[
        const FormTitle(
          title: '充值',
          subtitle: '充值您的账户余额',
        ),
        const SizedBox(height: 20),

        // 参考图里「用户名」用的是「人形」图标
        FieldInput(
          controller: _user,
          hint: '用户名',
          icon: Icons.person_outline,
          hasError: _userError != null,
          errorTick: _tick,
          onChanged: (_) {
            if (_userError != null) setState(() => _userError = null);
          },
        ),

        const SizedBox(height: 12),

        // 第二栏是账号密码（BSPHP 的 chong.lg 需要 userpwd），默认遮蔽输入
        FieldInput(
          controller: _pwd,
          hint: '密码',
          icon: Icons.lock_outline,
          obscure: true,
          hasError: _pwdError != null,
          errorTick: _tick,
          onChanged: (_) {
            if (_pwdError != null) setState(() => _pwdError = null);
          },
        ),

        const SizedBox(height: 12),

        FieldInput(
          controller: _card,
          hint: '卡密',
          icon: Icons.pin_outlined,
          hasError: _cardError != null,
          errorTick: _tick,
          onChanged: (_) {
            if (_cardError != null) setState(() => _cardError = null);
          },
          onSubmitted: (_) => _submit(),
        ),

        const SizedBox(height: 24),

        Center(
          child: PillButton(
            label: '提交数据',
            width: 170,
            loading: _loading,
            onPressed: _submit,
          ),
        ),

        // 结果提示：成功与失败用不同底色，占同一块位置。
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: _done
              ? const Padding(
                  padding: EdgeInsets.only(top: 18),
                  child: _SuccessTip(),
                )
              : (_errorMessage == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: _ErrorTip(message: _errorMessage!),
                    )),
        ),
      ],
    );
  }
}

/// 服务端结果的错误条。
///
/// 结构与登录页的提示条保持一致：这里的文字全部来自 C 侧翻译好的官方错误码，
/// 长度不可控（最长的那几条有 30 多个汉字），所以必须能换行而不是撑破布局。
class _ErrorTip extends StatelessWidget {
  const _ErrorTip({required this.message});

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline, size: 13, color: AuthColors.error),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.5,
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

class _SuccessTip extends StatelessWidget {
  const _SuccessTip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AuthColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: AuthColors.primary.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.check_circle_outline,
            size: 14,
            color: AuthColors.primary,
          ),
          SizedBox(width: 7),
          Text(
            '充值信息已提交，请等待到账',
            style: TextStyle(
              fontSize: 11.5,
              color: AuthColors.primary,
              fontFamily: kFontFamily,
              fontFamilyFallback: kFontFallback,
            ),
          ),
        ],
      ),
    );
  }
}
