// ---------------------------------------------------------------------------
// 工作台提示条（替代 .ui 里的 QStatusBar）
//
// 底部居中、宽 260、1.6 秒、深绿底 —— 工作台的提示频率高（登录 / 查询 / 加入
// 修改 / 删除 N 行），不能挡住右侧表格。
//
// 【同一条文案 400ms 内重复只保留最新一条】
// 早先的做法是「先 clearSnackBars 再 show」，但工作台的提示是连发的
// （登录成功 → 加入修改 → 查询 往往在几秒内发生），后一条一弹就把前一条立刻
// 抹掉，用户只看到最后那句，会以为前面的操作没生效。
//
// 现在只清掉**同一条内容**的重复提示（防连点堆叠），其余让它自然播完 1.6 秒。
// 用「记住上一条文案 + 时刻」而不是读 ScaffoldMessenger 的当前提示：后者没有
// 公开的 getter，读不到就只能整段清空 —— 那正是要避免的行为。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';

/// 在工作台底部弹一条轻提示。
///
/// [context] 必须是一个仍然 mounted 的 BuildContext —— 调用点要在 await 之后
/// 检查 `mounted`，否则会对已卸载的 ScaffoldMessenger 操作。
void showWorkSnack(BuildContext context, String message) {
  final ScaffoldMessengerState m = ScaffoldMessenger.of(context);
  final int now = DateTime.now().millisecondsSinceEpoch;

  /* 同一条文案在 [_dedupeWindowMs] 内重复：直接跳过，不 show 也不清队列。
   *
   * 早先这里调的是 `m.clearSnackBars()` —— 那是个真 bug：clearSnackBars 清的是
   * **整个队列**，不只是「同一条」。于是「登录成功 → 加入修改 → 查询」这种连发
   * 场景里，只要其中任意两条文案相同，中间那条不同文案的提示会被一起抹掉，
   * 用户看到屏幕上只剩最后一句，会以为中间那步没生效。
   *
   * 现在改成直接 return：既防住了连点堆叠（同一条不会排成一串），又不动别的
   * 提示 —— 与上面注释承诺的行为一致。 */
  if (_lastMessage == message && now - _lastAtMs < _dedupeWindowMs) {
    return;
  }

  _lastMessage = message;
  _lastAtMs = now;
  m.showSnackBar(
    SnackBar(
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: kFontBody,
          color: Colors.white,
          fontFamily: kFontFamily,
          fontFamilyFallback: kFontFallback,
        ),
      ),
      duration: const Duration(milliseconds: 1600),
      behavior: SnackBarBehavior.floating,
      backgroundColor: WorkColors.primaryDark,
      width: 260,
      // 圆角与工作台控件一致（3），不用 Material 默认的 4。
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadius),
      ),
      // 默认的内边距是 16/14，压在 260 宽的条里显得很胖。
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      elevation: 4,
    ),
  );
}

/// 上一条提示的文案与时刻：用于「同一条连点」去重。
String? _lastMessage;
int _lastAtMs = 0;

/// 同一条文案在这个窗口内重复出现时，只保留最新的一条（避免连点堆叠）。
const int _dedupeWindowMs = 400;
