// ---------------------------------------------------------------------------
// C 侧类型与内存布局的 Dart 镜像。
//
// 这里的每个常量、每个字段顺序、每个字符数组容量都必须与 src/pigeon_core.h
// 逐个对齐。对不齐不会编译报错，只会表现成「莫名其妙的判定结果」或字段整体
// 错位，所以改动任何一边都必须同时改另一边。
//
// 本文件不 import 包内其他文件，避免成环。
// ---------------------------------------------------------------------------
import 'dart:convert';
import 'dart:ffi';

// ---------------------------------------------------------------------------
// 通用：把一个定长 UTF-8 字符数组读成 Dart 字符串
// ---------------------------------------------------------------------------

/// 读一个 NUL 结尾的定长 UTF-8 字符数组。
///
/// [length] 必须显式传：`Array<T>` 上的长度只是编译期注解，运行期拿不到，
/// 所以只能由调用方给出（用下面那两个常量）。
///
/// 扫描上限就是这个长度，不会越过该字段去读结构体里的下一个字段 ——
/// 这比「一直读到 NUL 为止」稳，代价是几行循环。
///
/// `allowMalformed: true`：C 侧对定长字段是按**字节**截断的（虽然已经尽量
/// 切在字符边界上，但服务端给的数据本身也可能就不是合法 UTF-8）。默认的严格
/// 模式遇到非法序列会抛 FormatException —— 调用点（每秒一次的状态快照、
/// 登录提交）没有 catch，异常会顺着定时器回调抛出去，表现成「表格状态列
/// 不再刷新」或「提交中永远不结束」。这里降级成替换字符，保证解码永不抛。
String readFixedUtf8(Array<Uint8> bytes, int length) {
  final List<int> codes = <int>[];
  for (int i = 0; i < length; i++) {
    final int byte = bytes[i];
    if (byte == 0) {
      break;
    }
    codes.add(byte);
  }
  return utf8.decode(codes, allowMalformed: true);
}

// ---------------------------------------------------------------------------
// 状态码
// ---------------------------------------------------------------------------

/// 调用状态码。对应 C 侧 `PC_OK` / `PC_ERR_*`。
///
/// `form` / `mapEmpty` 是正常的业务结论，不是程序错误。
///
/// 这里**没有**「账号密码不对」「用户名已被占用」这类码：那些结论由服务端
/// 裁决，统一落在 [server] 上，具体原因在 `PcAuthResult.message` 里
/// （服务端返回的原始提示语）。本地不存在「不发请求也能判定账号」的
/// 路径，所以也就不需要对应的状态码。
abstract final class PcStatus {
  static const int ok = 0;

  static const int invalidArg = -1;
  static const int bufferSmall = -2;

  static const int form = -10;
  static const int mapEmpty = -13;

  /// 请求没走通（DNS / 连接 / 超时 / 非 200）。可以重试。
  static const int network = -14;

  /// 服务端明确拒绝，[PcAuthResult.message] 里是翻译过的官方提示语。
  static const int server = -15;

  /// 本地文件读写失败（记住密码的持久化等）。
  static const int io = -16;
}

/// 字段级判定码。对应 C 侧 `PC_FIELD_*`。
abstract final class PcField {
  static const int ok = 0;
  static const int empty = 1;
  static const int tooShort = 2;
  static const int mismatch = 3;
  static const int badCard = 4;

  /// 长度不落在要求的区间里（用户名要求 6-16 位）。
  static const int badLength = 5;

  /// 含不允许的字符（用户名只能是字母和数字）。
  static const int badChars = 6;

  /// 超过本地上限（防止超长输入被传输层静默截断，见 C 侧 `PC_FIELD_TOO_LONG`）。
  static const int tooLong = 7;
}

// ---------------------------------------------------------------------------
// 表单结果
// ---------------------------------------------------------------------------

/// `pc_form_result` 的内存布局映射（C 侧 6 个 int32）。
///
/// 字段顺序必须与 `src/pigeon_core.h` 里的结构体完全一致 —— FFI 是按偏移读的。
final class PcFormResultNative extends Struct {
  @Int32()
  external int user;

  @Int32()
  external int pwd;

  @Int32()
  external int pwd2;

  @Int32()
  external int card;

  /// 充值页「账号密码」槽位。注册页的确认密码走 [pwd2]，两者不再复用。
  @Int32()
  external int pwdAcc;

  @Int32()
  external int formOk;
}

/// 把 C 内存里的结构体拷成纯 Dart 值对象，之后与那块内存再无关系
/// （调用方随即会释放它）。
///
/// 刻意写成扩展而不是 [PcFormResultNative] 的方法：FFI 的 Struct 子类只应该
/// 承担「内存布局」这一件事，多挂成员容易踩到 FFI 对结构体类的限制。
extension PcFormResultNativeX on PcFormResultNative {
  PcFormResult toDart() => PcFormResult(
        user: user,
        pwd: pwd,
        pwd2: pwd2,
        card: card,
        pwdAcc: pwdAcc,
        formOk: formOk != 0,
      );
}

/// 一次表单校验的逐字段结论（值对象）。
final class PcFormResult {
  const PcFormResult({
    required this.user,
    required this.pwd,
    required this.pwd2,
    required this.card,
    required this.pwdAcc,
    required this.formOk,
  });

  /// 用户名槽位，取值见 [PcField]。
  final int user;

  /// 密码槽位，取值见 [PcField]。
  final int pwd;

  /// 注册页「确认密码」槽位（充值页不再复用这个槽位）。
  final int pwd2;

  /// 卡密槽位，取值见 [PcField]。
  final int card;

  /// 充值页「账号密码」槽位，取值见 [PcField]。
  final int pwdAcc;

  /// 全部槽位是否通过。
  final bool formOk;
}

/// 提示语的字符数组容量。必须等于 C 侧 `PC_AUTH_MSG_LEN`。
const int kAuthMsgLen = 256;

/// 返回数据的字符数组容量。必须等于 C 侧 `PC_AUTH_DATA_LEN`。
const int kAuthDataLen = 512;

/// `pc_auth_result` 的内存布局映射。
///
/// 前两个字段之后是两个定长字符数组，顺序与容量都必须与
/// `src/pigeon_core.h` 一致 —— 不一致不会编译报错，只会读到错位的内容。
final class PcAuthResultNative extends Struct {
  @Int32()
  external int status;

  /// 内嵌结构体。dart:ffi 支持直接内嵌，不需要手工摊平字段。
  external PcFormResultNative form;

  @Array(kAuthMsgLen)
  external Array<Uint8> message;

  @Array(kAuthDataLen)
  external Array<Uint8> data;
}

extension PcAuthResultNativeX on PcAuthResultNative {
  PcAuthResult toDart() => PcAuthResult(
        status: status,
        form: form.toDart(),
        message: readFixedUtf8(message, kAuthMsgLen),
        data: readFixedUtf8(data, kAuthDataLen),
      );
}

/// 一次认证调用的完整结果。
final class PcAuthResult {
  const PcAuthResult({
    required this.status,
    required this.form,
    required this.message,
    required this.data,
  });

  /// 取值见 [PcStatus]。
  final int status;

  /// 逐字段结论。即使 [status] 是 `network` / `server`，
  /// [PcFormResult.formOk] 也会是 true —— 表单本身是通过的。
  final PcFormResult form;

  /// 给用户看的提示语。成功时是「登录成功」这类短句；
  /// 失败时是翻译过的服务端错误码，未收录的码原样呈现。
  final String message;

  /// 服务端返回的原文。登录成功时就是 Token。
  final String data;

  bool get ok => status == PcStatus.ok;
}
