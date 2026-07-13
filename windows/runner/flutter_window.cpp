#include "flutter_window.h"

#include <cmath>
#include <cstdint>
#include <optional>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

bool ReadDoubleArgument(const flutter::EncodableMap& arguments,
                        const char* key,
                        double* value) {
  auto it = arguments.find(flutter::EncodableValue(key));
  if (it == arguments.end()) {
    return false;
  }

  if (const auto* double_value = std::get_if<double>(&it->second)) {
    *value = *double_value;
    return true;
  }
  if (const auto* int_value = std::get_if<int32_t>(&it->second)) {
    *value = static_cast<double>(*int_value);
    return true;
  }
  if (const auto* int64_value = std::get_if<int64_t>(&it->second)) {
    *value = static_cast<double>(*int64_value);
    return true;
  }
  return false;
}

bool SendTrustedMouseClick(HWND hwnd, double logical_x, double logical_y) {
  if (hwnd == nullptr) {
    return false;
  }

  const UINT dpi = GetDpiForWindow(hwnd);
  const double scale = dpi > 0 ? static_cast<double>(dpi) / 96.0 : 1.0;
  POINT screen_point = {
      static_cast<LONG>(std::lround(logical_x * scale)),
      static_cast<LONG>(std::lround(logical_y * scale)),
  };

  if (!ClientToScreen(hwnd, &screen_point)) {
    return false;
  }

  SetForegroundWindow(hwnd);
  SetCursorPos(screen_point.x, screen_point.y);
  Sleep(25);

  INPUT inputs[2] = {};
  inputs[0].type = INPUT_MOUSE;
  inputs[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
  inputs[1].type = INPUT_MOUSE;
  inputs[1].mi.dwFlags = MOUSEEVENTF_LEFTUP;

  return SendInput(2, inputs, sizeof(INPUT)) == 2;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  native_input_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "golden_p/native_input",
          &flutter::StandardMethodCodec::GetInstance());
  native_input_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "click") {
          result->NotImplemented();
          return;
        }

        const auto* arguments =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (arguments == nullptr) {
          result->Error("bad_args", "Expected a map with x and y.");
          return;
        }

        double x = 0.0;
        double y = 0.0;
        if (!ReadDoubleArgument(*arguments, "x", &x) ||
            !ReadDoubleArgument(*arguments, "y", &y)) {
          result->Error("bad_args", "Expected numeric x and y.");
          return;
        }

        result->Success(flutter::EncodableValue(
            SendTrustedMouseClick(GetHandle(), x, y)));
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
