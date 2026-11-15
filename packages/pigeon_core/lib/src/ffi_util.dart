// ---------------------------------------------------------------------------
// FFI 调用辅助。
//
// 核心包对字符串的约定是「入参由调用方分配、调用方释放，C 侧只读」，
// 所以每次调用都得自己申请 UTF-8 缓冲。这里把那套 try/finally 收在一个地方，
// 免得每个调用点各写一遍、漏掉一处就泄漏。
//
// 只依赖 types.dart，不要反向 import —— 否则成环。
// ---------------------------------------------------------------------------
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'types.dart';

/// 把 [args] 全部转成 UTF-8 裸指针交给 [body]，无论 [body] 正常返回还是抛异常，
/// 退出时都会释放。
///
/// 指针只在 [body] 执行期间有效 —— 不要把它存下来带出去。
///
/// 【分配器必须配对】toNativeUtf8() 用的是 malloc，释放就必须用 malloc.free。
/// 早先这里写的是 calloc.free：在当前 UCRT 下两者落到同一个堆上看不出问题，
/// 但只要 toNativeUtf8 的默认分配器换掉（或换 CRT / 换平台），立刻变成
/// 「用错误的释放器释放」——堆损坏，而且崩溃点离这里很远。
T withUtf8Args<T>(List<String> args, T Function(List<Pointer<Utf8>>) body) {
  final List<Pointer<Utf8>> pointers = <Pointer<Utf8>>[];
  try {
    for (final String arg in args) {
      pointers.add(arg.toNativeUtf8());
    }
    return body(pointers);
  } finally {
    for (final Pointer<Utf8> pointer in pointers) {
      // 与 toNativeUtf8() 的 malloc 配对（见上面的说明）。
      malloc.free(pointer);
    }
  }
}

/// 调用一个「通过 `int32_t*` 出参返回结果」的 C 函数并读出它。
///
/// 返回码不是 [PcStatus.ok] 时给 [fallback] —— 这些查询接口只有在传空指针时
/// 才会失败，而 Dart 侧不可能传空指针，所以实际走不到。
int readInt32Out(int Function(Pointer<Int32>) invoke, {int fallback = 0}) {
  final Pointer<Int32> out = calloc<Int32>();
  try {
    if (invoke(out) != PcStatus.ok) {
      return fallback;
    }
    return out.value;
  } finally {
    calloc.free(out);
  }
}

/// 同 [readInt32Out]，用于 `int64_t*` 出参。
int readInt64Out(int Function(Pointer<Int64>) invoke, {int fallback = 0}) {
  final Pointer<Int64> out = calloc<Int64>();
  try {
    if (invoke(out) != PcStatus.ok) {
      return fallback;
    }
    return out.value;
  } finally {
    calloc.free(out);
  }
}
