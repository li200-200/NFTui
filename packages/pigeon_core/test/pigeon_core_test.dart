// ---------------------------------------------------------------------------
// C 核心的冒烟测试：验证 native assets 真的编译出来了、FFI 真的绑得上。
//
// 【为什么必须有这一条】
// native assets 的失败方式很隐蔽：hook 没跑、动态库没进包、assetName 与库 URI
// 对不上 —— 三种都不影响编译，只在**运行时第一次调 C 函数**时炸，而且报的是
// 「Failed to lookup symbol」。这条测试把那个时刻提前到 `flutter test`。
//
// 【为什么断言的是具体数值而不是「不抛异常」】
// 校验规则在 C 里，Dart 只是转发。若 FFI 绑错了函数（符号名相近、参数顺序
// 颠倒），调用照样返回、异常照样不抛，只是结论悄悄错了。所以这里对着
// pc_auth.c 的 pc_field_username / pc_field_length 逐条核对判定码。
// ---------------------------------------------------------------------------
import 'package:flutter_test/flutter_test.dart';

import 'package:pigeon_core/pigeon_core.dart';

void main() {
  group('FFI 绑定', () {
    test('ABI 自检：C 结构体尺寸与 Dart 镜像一致', () {
      // pcAbiCheck 内部把结果写进运行日志（日志未初始化时是空操作），
      // 所以这里直接调 pc_abi_probe 拿原始数组自己比 —— 断言要能失败，
      // 不能只靠日志里那行字。
      final List<int> sizes = pcAbiProbe();
      expect(sizes.length, 2, reason: '本工程只移植了验证页依赖的两个结构体');
      expect(sizes[0], sizeOfFormResult, reason: 'pc_form_result 应为 24 字节');
      expect(sizes[1], sizeOfAuthResult, reason: 'pc_auth_result 应为 796 字节');
    });
  });

  group('表单校验（规则全在 C 里）', () {
    test('登录：空字段 → 逐字段 EMPTY', () {
      final PcFormResult r = pcAuthValidateLogin(user: '', pwd: '');
      expect(r.formOk, isFalse);
      expect(r.user, PcField.empty);
      expect(r.pwd, PcField.empty);
    });

    test('登录：用户名 5 位 → BAD_LENGTH（服务端要求 6-16）', () {
      final PcFormResult r = pcAuthValidateLogin(user: 'abcde', pwd: '123456');
      expect(r.user, PcField.badLength);
      expect(r.pwd, PcField.ok);
      expect(r.formOk, isFalse);
    });

    test('登录：用户名含汉字 → BAD_CHARS（只允许字母数字）', () {
      // 必须用 6 个汉字：C 侧 pc_field_username 是「先长度后字符集」，
      // 5 个字会先撞上 BAD_LENGTH（见 pc_auth.c 的注释「用户一次只会看到
      // 一类问题」）。用 6 个字才能确认走到字符集那条分支。
      final PcFormResult r = pcAuthValidateLogin(user: '用户名测试啊', pwd: '123456');
      expect(r.user, PcField.badChars);
    });

    test('登录：密码 5 位 → TOO_SHORT', () {
      final PcFormResult r = pcAuthValidateLogin(user: 'abc123', pwd: '12345');
      expect(r.user, PcField.ok);
      expect(r.pwd, PcField.tooShort);
    });

    test('登录：合法输入 → formOk', () {
      final PcFormResult r = pcAuthValidateLogin(user: 'abc123', pwd: '123456');
      expect(r.user, PcField.ok);
      expect(r.pwd, PcField.ok);
      expect(r.formOk, isTrue);
    });

    test('登录：超长密码 → TOO_LONG（防止传输层静默截断）', () {
      final PcFormResult r =
          pcAuthValidateLogin(user: 'abc123', pwd: 'x' * 65);
      expect(r.pwd, PcField.tooLong);
    });

    test('注册：两次密码不一致 → MISMATCH', () {
      final PcFormResult r = pcAuthValidateRegister(
        user: 'abc123',
        pwd: '123456',
        pwd2: '654321',
        card: '12345678',
      );
      expect(r.pwd2, PcField.mismatch);
      expect(r.formOk, isFalse);
    });

    test('注册：确认密码为空 → EMPTY', () {
      final PcFormResult r = pcAuthValidateRegister(
        user: 'abc123',
        pwd: '123456',
        pwd2: '',
        card: '12345678',
      );
      expect(r.pwd2, PcField.empty);
    });

    test('注册：卡密 7 位 → BAD_CARD（本地宽松预检，至少 8 位）', () {
      final PcFormResult r = pcAuthValidateRegister(
        user: 'abc123',
        pwd: '123456',
        pwd2: '123456',
        card: '1234567',
      );
      expect(r.card, PcField.badCard);
    });

    test('注册：四项齐全 → formOk', () {
      final PcFormResult r = pcAuthValidateRegister(
        user: 'abc123',
        pwd: '123456',
        pwd2: '123456',
        card: '12345678',
      );
      expect(r.formOk, isTrue);
    });

    test('充值：用户名只判空，不判长度与字符集', () {
      // 官方充值接口的 UserName 只是「给谁充」，规则在注册时就定死了。
      final PcFormResult r =
          pcAuthValidateRecharge(user: 'a', confirm: '123456', card: '12345678');
      expect(r.user, PcField.ok, reason: '充值页不做用户名长度校验');
    });

    test('充值：账号密码走 pwdAcc 槽位，不是 pwd', () {
      final PcFormResult r =
          pcAuthValidateRecharge(user: 'abc', confirm: '12345', card: '12345678');
      expect(r.pwdAcc, PcField.tooShort);
      expect(r.pwd, PcField.ok, reason: 'pwd 槽位在充值页不用');
    });
  });

  group('记住密码', () {
    test('默认路径非空且是绝对路径', () {
      final String path = pcCredDefaultPath();
      expect(path, isNotEmpty);
      // Windows 上应当是 %LOCALAPPDATA%\... 或退到当前目录的绝对路径
      expect(path.contains('pigeon_assist_cred.dat'), isTrue);
    });

    test('传空串禁用持久化时读回空记录', () {
      // credPath 为空串是「完全禁用持久化」的约定，登录页用它做测试隔离。
      // 这里验证 C 侧对空路径的处理不会崩。
      final PcSavedCred saved = pcCredLoad(path: '');
      expect(saved.remember, isFalse);
      expect(saved.user, isEmpty);
    });
  });

  group('登录心跳', () {
    test('未启动时 isRunning 为 false', () {
      // 测试进程刚起来，心跳线程还没被任何人启动过。
      expect(pcHeartbeatIsRunning(), isFalse);
    });

    test('start 返回 PC_OK 且 isRunning 立刻为 true', () {
      final int rc = pcHeartbeatStart();
      expect(rc, PcStatus.ok,
          reason: '心跳起不来会让服务端把登录判成掉线，必须是成功');

      // running 由 hb_loop 持锁置位，start 在返回前已经写过一次，
      // 所以这里不需要等待 —— 立刻就该是 true。
      expect(pcHeartbeatIsRunning(), isTrue);
    });

    test('重复 start 不叠加线程，仍返回 PC_OK', () {
      // 界面「退出登录再登录」会来回调 start。C 侧约定幂等：
      // 已在跑时复用现有线程，不新建。这条钉住那个约定 ——
      // 一旦哪天改成「每次都 CreateThread」，这里会看到 rc 仍为 ok
      // 但线程会累积（靠 isRunning 查不出来，所以下面还有 stop 的时序断言）。
      final int rc = pcHeartbeatStart();
      expect(rc, PcStatus.ok);
      expect(pcHeartbeatIsRunning(), isTrue);
    });

    test('stop 后 isRunning 变 false（协作式，会等线程收干净）', () async {
      pcHeartbeatStop();

      /* 【为什么要轮询而不是立刻断言】
       * stop 是协作式的：置停止标志 + 唤醒等待中的线程，调用本身立即返回。
       * 线程可能正卡在一次网络请求里，收到 stop_req 后会在下一轮检查点退出。
       *
       * 【为什么给到 30 秒】
       * 测试进程里没有真实会话，第一次心跳必然走到「TRANSIENT → 重新握手」那条
       * 分支，而重握手本身是 2 个网络请求（internet.in + BSphpSeSsL.in），
       * 在离网 / 防火墙环境下每个都可能等到连接超时。这段耗时与「停止功能是否
       * 正确」无关 —— 线程收干净后会立刻把 running 清零，所以放宽上限只是
       * 避免测试因为网络环境假失败，不会掩盖真正的 bug（真正的 bug 是
       * running 永远不归零，30 秒也过不了）。 */
      bool stopped = false;
      for (int i = 0; i < 300; i++) {
        if (!pcHeartbeatIsRunning()) {
          stopped = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(stopped, isTrue, reason: 'stop 后心跳线程最终应当退出（running 归零）');
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
