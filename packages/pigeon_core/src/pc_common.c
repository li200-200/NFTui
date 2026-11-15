/* ---------------------------------------------------------------------------
 * pc_common.h 的实现。纯函数、无状态、不分配内存。
 * ------------------------------------------------------------------------- */

#include "pc_common.h"

#include <string.h>

/* 只认 ASCII 空白。见 pc_common.h 里关于与 Dart trim() 差异的说明。 */
static int pc_is_ascii_space(unsigned char c) {
  return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' ||
         c == '\f';
}

/* ASCII 小写化。非 ASCII 字节原样返回（UTF-8 多字节序列不参与大小写折叠）。 */
static int pc_ascii_lower(int c) {
  return (c >= 'A' && c <= 'Z') ? c + ('a' - 'A') : c;
}

pc_slice pc_slice_of(const char* s) {
  pc_slice out;

  if (s == NULL) {
    out.ptr = NULL;
    out.len = 0;
    return out;
  }

  out.ptr = s;
  out.len = strlen(s);
  return out;
}

pc_slice pc_trim(const char* s) {
  pc_slice out;
  size_t begin = 0;

  out = pc_slice_of(s);
  if (out.ptr == NULL) {
    return out;
  }

  while (begin < out.len && pc_is_ascii_space((unsigned char)out.ptr[begin])) {
    begin++;
  }
  while (out.len > begin &&
         pc_is_ascii_space((unsigned char)out.ptr[out.len - 1])) {
    out.len--;
  }

  out.ptr += begin;
  out.len -= begin;
  return out;
}

size_t pc_utf8_count(const pc_slice* s) {
  size_t count = 0;
  size_t i;

  if (s == NULL || s->ptr == NULL) {
    return 0;
  }

  /* UTF-8 里续字节形如 10xxxxxx；数「非续字节」就是数码点。 */
  for (i = 0; i < s->len; i++) {
    if (((unsigned char)s->ptr[i] & 0xC0u) != 0x80u) {
      count++;
    }
  }
  return count;
}

int pc_slice_eq(const pc_slice* s, const char* literal) {
  size_t n;

  if (s == NULL || s->ptr == NULL || literal == NULL) {
    return 0;
  }

  n = strlen(literal);
  return (s->len == n) && (memcmp(s->ptr, literal, n) == 0);
}

int pc_slice_ieq(const pc_slice* s, const char* literal) {
  size_t n;
  size_t i;

  if (s == NULL || s->ptr == NULL || literal == NULL) {
    return 0;
  }

  n = strlen(literal);
  if (s->len != n) {
    return 0;
  }

  for (i = 0; i < n; i++) {
    if (pc_ascii_lower((unsigned char)s->ptr[i]) !=
        pc_ascii_lower((unsigned char)literal[i])) {
      return 0;
    }
  }
  return 1;
}

int pc_slice_equal(const pc_slice* a, const pc_slice* b) {
  if (a == NULL || b == NULL || a->ptr == NULL || b->ptr == NULL) {
    return 0;
  }
  if (a->len != b->len) {
    return 0;
  }
  if (a->len == 0) {
    return 1;
  }
  return memcmp(a->ptr, b->ptr, a->len) == 0;
}

size_t pc_utf8_fit(const char* s, size_t len) {
  if (s == NULL || len == 0) {
    return 0;
  }
  /* 【不要读 s[len]】
   *
   * 早先的实现从 s[len] 开始向前回退，并依赖调用方保证 len <= strlen(s)：
   * 一旦某个新调用点传进更大的 len，就是一次分配区外的 1 字节读。
   * 这种前置条件没有任何编译期或运行期保护，靠注释约束迟早出事。
   *
   * 现在只往回看 s[len-1]（一定在 [0, len) 之内，必然可读），
   * 数清楚截断点之前有几个「续字节」：
   *   0 个 → 正好切在字符边界，原样返回；
   *   k 个 → 说明 s[len] 落在一个多字节字符中间，回退到该字符的起始字节。 */
  {
    size_t back = 0;
    while (back < 3 && back < len &&
           ((unsigned char)s[len - 1 - back] & 0xC0u) == 0x80u) {
      back++;
    }
    if (back == 0) {
      return len;
    }
    /* back 是续字节个数。回退 back 个字节到首字节位置，再确认它确实是一个
     * 多字节字符的起始字节；不是的话（说明输入本身就不是合法 UTF-8）
     * 保持原长度，避免把合法内容也砍掉。 */
    {
      size_t start = len - back - 1;
      unsigned char lead = (unsigned char)s[start];
      size_t need;
      if ((lead & 0xE0u) == 0xC0u) {
        need = 2;
      } else if ((lead & 0xF0u) == 0xE0u) {
        need = 3;
      } else if ((lead & 0xF8u) == 0xF0u) {
        need = 4;
      } else {
        return len; /* 不是合法首字节：不动 */
      }
      if (start + need > len) {
        return start; /* 这个字符确实被截断了：回退到它的起点 */
      }
      return len;
    }
  }
}
