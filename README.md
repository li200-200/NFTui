# app_ui

工作台界面 —— 把 `untitled.ui`（QMainWindow）与 `config.ui`（设置抽屉）翻译成
Flutter Windows 桌面端 UI。

## 文档

| 文档 | 内容 |
|---|---|
| **[CHANGE_GUIDE.md](CHANGE_GUIDE.md)** | **改动指南：控件 / UI / 数据 / 测试。以这份为准。** |
| [UI_GUIDE.md](UI_GUIDE.md) | 早期速查手册，**已过期**（行号漂移、仍在讲已删除的控件），仅作历史参考 |
| `untitled.ui` | 主窗口的控件来源（Qt Designer XML） |
| `config.ui` | 设置抽屉的控件来源（Qt Designer XML） |

## 命令

```powershell
flutter analyze          # 必须 No issues found!
flutter test             # 必须 All tests passed!（69 个用例）
flutter run -d windows   # 开发
flutter build windows --release
# 产物：build\windows\x64\runner\Release\app_ui.exe
```

## 结构

```
lib\
├── main.dart              入口 + 窗口设置（1048x682，最小 880x620）
├── theme.dart             颜色 / 尺寸 / 时长 / 曲线 / PanelMetrics 三档
├── models.dart            表格列定义（3 套）+ 行模型 + 示例数据
├── pages\main_page.dart   页面骨架 + 全部状态持有者
└── widgets\
    ├── object_names.dart  ★ .ui 的 objectName 常量表（改控件的起点）
    ├── panel_controls.dart 桶文件（一行 import 拿到全部通用控件）
    ├── drawer_panels.dart  三个抽屉面板
    ├── nav_bar.dart        底部图标条 + 抽屉外壳 + NavDestination
    └── …                   表格 / 标签条 / 提示条 / 标题条
```

## 三条铁律

1. 颜色、尺寸只写在 `lib/theme.dart`
2. 每个 `TextEditingController` 必须 `dispose()`
3. 新增控件必须挂 `ValueKey(objectName)`（objectName 取自 `.ui`）

详细说明见 [CHANGE_GUIDE.md](CHANGE_GUIDE.md)。
