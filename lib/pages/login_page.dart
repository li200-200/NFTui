// ---------------------------------------------------------------------------
// 登录页
//
// 对照参考图 登录.PNG 的结构：
//   标题「登录」
//   说明「请用您的用户名登录」
//   小字 + 绿色链接「若您还没有账号,点击这里 注册账号」
//   用户名 / 密码 两个输入框（密码框右侧有眼睛）
//   [记住密码] [自动登录]
//   胶囊按钮「登录」
//   「余额不足？ 充值」
//
// 校验反馈：输入不完整时不弹任何文字，
// 而是让对应的输入框「边框变红 + 左右抖两下」。
// 只有服务端返回的账号错误才走错误提示条（信息确实非说不可）。
//
// 自动登录：勾选后登录成功会把标记随账号密码一起写盘，下次启动自动提交
// 一次；失败则取消该标记并停在登录页，账号密码仍保留并回填。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/auth_scaffold.dart';
import 'package:app_ui/widgets/auth_controls.dart';
import 'package:app_ui/widgets/form_messages.dart';
import 'package:pigeon_core/pigeon_core.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onGoRegister,
    required this.onGoRecharge,
    required this.onLoginSuccess,
    this.credPath,
  });

  final VoidCallback onGoRegister;
  final VoidCallback onGoRecharge;

  /// 登录成功后的回调，参数是用户名
  final ValueChanged<String> onLoginSuccess;

  /// 「记住密码」的存储路径。
  ///
  /// 不传就用 C 侧按平台给的默认路径；传空串则**完全禁用**持久化
  /// （测试里用它隔离，避免读到/写坏真实机器上记住的账号）。
  final String? credPath;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pwd = TextEditingController();

  bool _remember = true;
  bool _autoLogin = false;
  bool _obscure = true;
  bool _loading = false;

  /// 「自动登录」每次启动只尝试一次，失败后不再重试。
  bool _autoLoginTried = false;

  /// 记住密码的文件路径。空串 = 禁用持久化。
  late final String _credPath = widget.credPath ?? pcCredDefaultPath();

  /// 每次点提交自增，交给 FieldInput 用来重新触发抖动
  int _tick = 0;

  /// 字段级错误：null 表示无错
  String? _userError;
  String? _pwdError;

  /// 只有服务端结果才出文字
  String? _globalError;

  @override
  void initState() {
    super.initState();
    _restoreSavedCred();
  }

  @override
  void dispose() {
    _user.dispose();
    _pwd.dispose();
    super.dispose();
  }

  /// 启动时把上次「记住密码」的账号密码填回输入框。
  void _restoreSavedCred() {
    if (_credPath.isEmpty) {
      return;
    }
    final PcSavedCred saved = pcCredLoad(path: _credPath);
    if (!saved.remember) {
      return;
    }
    _user.text = saved.user;
    _pwd.text = saved.pwd;
    _remember = true;
    _autoLogin = saved.autoLogin;

    // 上次勾了「自动登录」且确实存下了账号密码 → 启动后自动提交一次。
    // 放到首帧之后再跑：initState 里不能 setState，而 _submit 会改到界面。
    if (_autoLogin && saved.user.isNotEmpty && saved.pwd.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoLogin());
    }
  }

  /// 启动时的自动登录：只跑一次，失败就停在登录页（见 [_cancelAutoLogin]）。
  Future<void> _tryAutoLogin() async {
    if (!mounted || _autoLoginTried) return;
    _autoLoginTried = true;
    await _submit(isAuto: true);
  }

  /// 自动登录失败：取消「自动登录」勾选，账号密码保留。
  ///
  /// 需求：验证失败后停留在登录页，且下次启动不再自动提交 —— 所以要把
  /// 标记写回磁盘，而不是只改内存里的勾选态。
  void _cancelAutoLogin() {
    if (!_autoLogin) return;
    setState(() => _autoLogin = false);
    _persistSavedCred();
  }

  /// 登录成功后：勾了「记住密码」就把账号密码写盘，否则写空记录（清空）。
  void _persistSavedCred() {
    if (_credPath.isEmpty) {
      return;
    }
    // 「自动登录」只在「记住密码」的前提下才有意义，一并只写有效组合。
    pcCredSave(
      path: _credPath,
      user: _remember ? _user.text.trim() : '',
      pwd: _remember ? _pwd.text : '',
      remember: _remember,
      autoLogin: _remember && _autoLogin,
    );
  }

  /// 取消勾选「记住密码」：立刻清掉之前记住的内容，别等下次登录才覆盖。
  void _forgetSavedCred() {
    if (_credPath.isEmpty) {
      return;
    }
    pcCredSave(
      path: _credPath,
      user: '',
      pwd: '',
      remember: false,
      autoLogin: false,
    );
  }

  Future<void> _submit({bool isAuto = false}) async {
    if (_loading) return;

    // ---- 第一段：表单校验（同步，不碰网络） ----
    //
    // 传原始文本：trim 与否是业务规则的一部分，由 C 侧统一说了算。
    // 这一步几微秒就回来，所以表单没过时能立刻红框抖动，
    // 不会先跳一下「提交中」再退回来。
    final PcFormResult form =
        pcAuthValidateLogin(user: _user.text, pwd: _pwd.text);
    if (!form.formOk) {
      _tick++;
      setState(() {
        _userError = userFieldMessage(form.user);
        _pwdError = passwordFieldMessage(form.pwd);
        _globalError = null;
      });
      return;
    }

    // ---- 第二段：提交给服务端（这一步才可能等网络） ----
    setState(() {
      _loading = true;
      _globalError = null;
    });

    /* 【必须兜住异常】pcAuthLogin 走 Isolate.run：isolate 创建失败、Dart 侧
     * 内存耗尽、或 FFI 层抛错时，异常会直接冒到 Zone。早先这里没有 try，
     * 于是 _loading 永远停在 true —— 按钮永久置灰、转圈永不停止，
     * 用户只能关窗重开。这里补上与 work_page 一致的 try/finally。 */
    PcAuthResult result;
    try {
      result = await pcAuthLogin(user: _user.text, pwd: _pwd.text);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _globalError = '登录请求异常：$e';
      });
      if (isAuto) _cancelAutoLogin();
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
        _globalError = null;
      });
      if (isAuto) _cancelAutoLogin();
      return;
    }

    if (result.status == PcStatus.ok) {
      setState(() => _loading = false);
      // 登录成功才落盘：没成功的账号不该被「记住」。
      _persistSavedCred();
      // 回传用户填的名字（不是服务端返回的 Token）—— 工作台只用它来显示。
      widget.onLoginSuccess(_user.text.trim());
      return;
    }

    // 剩下两类都属于「非说不可」，统一走错误提示条：
    //   server  服务端拒绝（账号密码不对、已到期、被顶下线…）
    //   network 连不上服务器
    // 文案由 C 侧给，错误码已经翻译成官方提示语。
    setState(() {
      _loading = false;
      _globalError = result.message.isEmpty ? '登录失败，请稍后重试' : result.message;
    });
    // 自动登录失败：停在登录页，同时取消「自动登录」避免每次启动都失败一次。
    if (isAuto) _cancelAutoLogin();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      // 登录页是首页，没有上一级，所以不传 onBack —— 右上角只显示关闭
      children: <Widget>[
        const FormTitle(
          title: '登录',
          subtitle: '请用您的用户名登录',
        ),
        const SizedBox(height: 8),

        // 「若您还没有账号,点击这里 注册账号」
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              '若您还没有账号,点击这里',
              style: TextStyle(
                fontSize: 12,
                color: AuthColors.textMuted,
                fontFamily: kFontFamily,
                fontFamilyFallback: kFontFallback,
              ),
            ),
            const SizedBox(width: 6),
            LinkText(
              text: '注册账号',
              fontSize: 12,
              onTap: widget.onGoRegister,
            ),
          ],
        ),
        const SizedBox(height: 30),

        FieldInput(
          controller: _user,
          hint: '用户名',
          icon: Icons.person_outline,
          hasError: _userError != null,
          errorTick: _tick,
          onChanged: (_) {
            if (_userError != null) setState(() => _userError = null);
          },
          onSubmitted: (_) => _submit(),
        ),

        const SizedBox(height: 16),

        FieldInput(
          controller: _pwd,
          hint: '密码',
          icon: Icons.lock_outline,
          obscure: _obscure,
          hasError: _pwdError != null,
          errorTick: _tick,
          onChanged: (_) {
            if (_pwdError != null) setState(() => _pwdError = null);
          },
          onSubmitted: (_) => _submit(),
          trailing: _EyeButton(
            obscured: _obscure,
            onTap: () => setState(() => _obscure = !_obscure),
          ),
        ),

        // 服务端返回的错误才出文字（比如账号密码不对），
        // 本地空输入一律用红框 + 抖动
        if (_globalError != null) ...<Widget>[
          const SizedBox(height: 12),
          _GlobalError(message: _globalError!),
        ],

        const SizedBox(height: 26),

        // 记住密码 / 自动登录
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            CheckPill(
              label: '记住密码',
              value: _remember,
              onChanged: (bool v) {
                setState(() {
                  _remember = v;
                  // 不记住密码就无从自动登录，两个勾一起收掉。
                  if (!v) _autoLogin = false;
                });
                // 取消勾选 = 立刻忘记，不等下次登录成功才覆盖。
                if (!v) _forgetSavedCred();
              },
            ),
            const SizedBox(width: 26),
            CheckPill(
              label: '自动登录',
              value: _autoLogin,
              onChanged: (bool v) {
                setState(() {
                  _autoLogin = v;
                  // 自动登录依赖保存下来的账号密码，勾上它必然要记住密码。
                  if (v) _remember = true;
                });
              },
            ),
          ],
        ),

        const SizedBox(height: 22),

        Center(
          child: PillButton(
            label: '登录',
            loading: _loading,
            onPressed: _submit,
          ),
        ),

        const SizedBox(height: 18),

        // 「余额不足？ 充值」
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              '余额不足？',
              style: TextStyle(
                fontSize: 12.5,
                color: AuthColors.textHint,
                fontFamily: kFontFamily,
                fontFamilyFallback: kFontFallback,
              ),
            ),
            const SizedBox(width: 10),
            LinkText(
              text: '充值',
              fontSize: 13,
              onTap: widget.onGoRecharge,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// 密码框右侧的睁眼 / 闭眼切换
class _EyeButton extends StatefulWidget {
  const _EyeButton({required this.obscured, required this.onTap});

  final bool obscured;
  final VoidCallback onTap;

  @override
  State<_EyeButton> createState() => _EyeButtonState();
}

class _EyeButtonState extends State<_EyeButton> {
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

/// 服务端结果的错误条
class _GlobalError extends StatelessWidget {
  const _GlobalError({required this.message});

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
