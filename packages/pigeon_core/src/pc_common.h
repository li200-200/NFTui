/* ---------------------------------------------------------------------------
 * C 核心内部公共工具。
 *
 * 这里的东西不属于对外契约（不在 pigeon_core.h 里），只在 src/ 内部使用。
 * 界面文案、错误码一律不在这里。
 * ------------------------------------------------------------------------- */

#ifndef PC_COMMON_H
#define PC_COMMON_H

#include <stddef.h>

/* 「一段字符串」的视图：指针 + 长度。
 *
 * 刻意不用裸 char* 反复传：入参裁剪（trim）之后如果只返回指针，长度信息就丢了，
 * 后面还得再 strlen 一次；而且带长度的视图能让比较逻辑短路得更干净。 */
typedef struct {
  const char* ptr;
  size_t len;
} pc_slice;

/* 不裁剪，长度取 strlen。 */
pc_slice pc_slice_of(const char* s);

/* 去掉首尾空白。
 *
 * 空白按 ASCII 判定（空格 / \t \n \r \v \f）—— 与 Dart 的 String.trim()
 * 在 ASCII 输入下等价；非 ASCII 空白（如全角空格）不处理，属于已知差异。 */
pc_slice pc_trim(const char* s);

/* 按「码点」计数，不是字节数。
 *
 * Dart 的 String.length 数的是 UTF-16 code unit；对 BMP 字符两者一致。
 * 直接数字节会让「用户名至少 3 个字符」对两个汉字（6 字节）误判为通过，
 * 所以这里必须按码点数。 */
size_t pc_utf8_count(const pc_slice* s);

/* 与 C 字面量比较，区分大小写。 */
int pc_slice_eq(const pc_slice* s, const char* literal);

/* 与 C 字面量比较，ASCII 大小写不敏感（对应 Dart 的 toLowerCase() 比较）。 */
int pc_slice_ieq(const pc_slice* s, const char* literal);

/* 两个 slice 比较，区分大小写。 */
int pc_slice_equal(const pc_slice* a, const pc_slice* b);

/* 把长度收缩到「不切断 UTF-8 序列」的位置，返回调整后的长度（<= len）。
 *
 * 定长字符数组的拷贝一律按字节截断，中文（3 字节）被切在中间就产生了非法
 * UTF-8 序列 —— 接收端（Dart 的 utf8.decode 默认严格模式）会直接抛异常，
 * 表现成「表格状态列不刷新」或「提交中永远不结束」。
 * 这里向前回退到该字符的起始字节，保证 [0, 返回值) 始终是合法 UTF-8 前缀。
 *
 * 调用方必须保证 len <= strlen(s)（各拷贝助手都按 strlen 算），
 * 这样读 s[len] 最多读到结尾的 NUL，是安全的。 */
size_t pc_utf8_fit(const char* s, size_t len);

#endif /* PC_COMMON_H */
