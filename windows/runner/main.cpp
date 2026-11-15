#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// 设计尺寸，必须与 lib/theme.dart 里的 kAuthWidth / kAuthHeight 一致
// （验证页按参考图逐像素校对：800x550）。
//
// 【为什么这里是验证页的尺寸而不是工作台的】
// 应用启动页是登录页，用户第一眼看到的就是 800x550 的验证界面；登录成功后
// 由 Dart 侧的 _enterWorkPage 把窗口改成工作台的 1048x682（见 lib/main.dart）。
// 反过来（原生按 1048x682 创建、Dart 再缩到 800x550）会出现「先闪一个大窗
// 再跳成小窗」，很扎眼。
//
// 注意：CreateWindow 收的是**物理像素**，而 Flutter 的 Size 是**逻辑像素**。
// 在 125% / 150% 缩放的屏幕上如果不补偿 DPI，窗口会比设计尺寸小一圈 ——
// 表单列 280 固定宽会显得更挤。
constexpr int kWindowWidth = 800;
constexpr int kWindowHeight = 550;

// 把窗口摆到当前显示器工作区的正中。
void CenterOnMonitor(HWND window, int width, int height) {
  HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {};
  info.cbSize = sizeof(MONITORINFO);
  if (!GetMonitorInfo(monitor, &info)) {
    return;
  }
  const RECT work = info.rcWork;
  const int x = work.left + ((work.right - work.left) - width) / 2;
  const int y = work.top + ((work.bottom - work.top) - height) / 2;
  SetWindowPos(window, nullptr, x, y, 0, 0,
               SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  //
  // 返回值必须处理：RPC_E_CHANGED_MODE 表示本线程已经以别的套间模型初始化过
  // （宿主 / 加载器注入的情况），此时后续任何 CoCreateInstance 都可能按错误的
  // 套间语义运行。失败时插件会在一个「COM 没准备好」的线程上调用 COM API，
  // 表现为随机的 0x800401F0（CO_E_NOTINITIALIZED）。
  const HRESULT com_hr = ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool com_initialized = SUCCEEDED(com_hr);
  if (!com_initialized && com_hr != RPC_E_CHANGED_MODE) {
    return EXIT_FAILURE;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(kWindowWidth, kWindowHeight);
  if (!window.Create(L"阿萨德", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // 先把位置摆好，但**不显示**。
  //
  // 窗口此刻还没挂上 Flutter 视图（FlutterWindow::OnCreate 在 Create 里才跑完），
  // 或者挂上了但首帧还没画完 —— 这两种情况下显示出来都只会是一块空白。
  // 显示交给 flutter_window.cpp 的首帧回调：那里 Show() 的时候，界面上已经是
  // 画好的内容了。
  {
    HWND handle = window.GetHandle();
    const UINT dpi = FlutterDesktopGetDpiForHWND(handle);
    const double scale = dpi / 96.0;
    const int physical_w = static_cast<int>(kWindowWidth * scale);
    const int physical_h = static_cast<int>(kWindowHeight * scale);
    CenterOnMonitor(handle, physical_w, physical_h);
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // 只在真正初始化成功时配对 CoUninitialize。RPC_E_CHANGED_MODE 的场合下
  // 调用它会把「别人初始化过」的 COM 关掉，影响同进程内的其它组件。
  if (com_initialized) {
    ::CoUninitialize();
  }
  return EXIT_SUCCESS;
}
