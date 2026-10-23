// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.
#include "media_kit_video_plugin.h"
#include "utils.h"

#include <Windows.h>
#include <vector>

namespace media_kit_video {

namespace {

// Windows display HDR (Advanced Color) state across active outputs.
// Returns 1 = HDR active (HDR10(PQ)=2 + HLG=3; no DV passthrough),
// 0 = no HDR on any active output, -1 = query unavailable.
int QueryAdvancedColorHdrState() {
  UINT32 path_count = 0;
  UINT32 mode_count = 0;
  if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &path_count,
                                  &mode_count) != ERROR_SUCCESS ||
      path_count == 0) {
    return -1;
  }
  std::vector<DISPLAYCONFIG_PATH_INFO> paths(path_count);
  std::vector<DISPLAYCONFIG_MODE_INFO> modes(mode_count);
  if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &path_count, paths.data(),
                         &mode_count, modes.data(), nullptr) != ERROR_SUCCESS) {
    return -1;
  }
  for (const auto& path : paths) {
    DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO info = {};
    info.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO;
    info.header.size = sizeof(info);
    info.header.adapterId = path.sourceInfo.adapterId;
    info.header.id = path.sourceInfo.id;
    if (DisplayConfigGetDeviceInfo(&info.header) == ERROR_SUCCESS &&
        info.advancedColorEnabled) {
      return 1;
    }
  }
  return 0;
}

// Read-only device capability query result (schema 1), the Windows display
// adapter: display HDR facts from Advanced Color; source specs echo back
// censusComplete=false — explicit unknown, never simulated support.
flutter::EncodableMap BuildRouteCapabilitiesResult(
    const flutter::MethodCall<flutter::EncodableValue>& method_call) {
  flutter::EncodableMap display;
  const int hdr_state = QueryAdvancedColorHdrState();
  if (hdr_state < 0) {
    display[flutter::EncodableValue("status")] =
        flutter::EncodableValue("queryUnavailable");
  } else {
    display[flutter::EncodableValue("status")] =
        flutter::EncodableValue("resolved");
    display[flutter::EncodableValue("hdrTypes")] =
        hdr_state == 1
            ? flutter::EncodableValue(std::vector<flutter::EncodableValue>{
                  flutter::EncodableValue(2), flutter::EncodableValue(3)})
            : flutter::EncodableValue(flutter::EncodableList{});
  }

  std::vector<flutter::EncodableValue> sources;
  if (const auto* arguments = method_call.arguments()) {
    if (const auto* args = std::get_if<flutter::EncodableMap>(arguments)) {
      if (const auto it = args->find(flutter::EncodableValue("sources"));
          it != args->end()) {
        if (const auto* requested = std::get_if<flutter::EncodableList>(
                &it->second)) {
          for (const auto& spec : *requested) {
            const auto* spec_map = std::get_if<flutter::EncodableMap>(&spec);
            if (spec_map == nullptr) {
              continue;
            }
            const auto key_it = spec_map->find(flutter::EncodableValue("key"));
            if (key_it == spec_map->end()) {
              continue;
            }
            const auto* key = std::get_if<std::string>(&key_it->second);
            if (key == nullptr) {
              continue;
            }
            flutter::EncodableMap entry;
            entry[flutter::EncodableValue("key")] =
                flutter::EncodableValue(*key);
            entry[flutter::EncodableValue("censusComplete")] =
                flutter::EncodableValue(false);
            entry[flutter::EncodableValue("reason")] =
                flutter::EncodableValue("notSupportedOnWindowsAdapter");
            entry[flutter::EncodableValue("decoders")] =
                flutter::EncodableValue(flutter::EncodableList{});
            sources.emplace_back(flutter::EncodableValue(entry));
          }
        }
      }
    }
  }

  flutter::EncodableMap result;
  result[flutter::EncodableValue("schema")] = flutter::EncodableValue(1);
  result[flutter::EncodableValue("platform")] =
      flutter::EncodableValue("windows");
  result[flutter::EncodableValue("display")] =
      flutter::EncodableValue(display);
  result[flutter::EncodableValue("sources")] =
      flutter::EncodableValue(flutter::EncodableList(std::move(sources)));
  result[flutter::EncodableValue("hdr")] = flutter::EncodableValue(
      flutter::EncodableMap{});
  return result;
}

}  // namespace

MediaKitVideoPlugin* MediaKitVideoPlugin::instance_ = nullptr;

void MediaKitVideoPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<MediaKitVideoPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

MediaKitVideoPlugin::MediaKitVideoPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar),
      video_output_manager_(std::make_unique<VideoOutputManager>(registrar)) {
  instance_ = this;
  flutter_window_ =
      ::GetAncestor(registrar->GetView()->GetNativeWindow(), GA_ROOT);
  original_window_proc_ = reinterpret_cast<WNDPROC>(
      ::SetWindowLongPtr(flutter_window_, GWLP_WNDPROC,
                         reinterpret_cast<LONG_PTR>(WindowProcDelegate)));

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "com.alexmercerind/media_kit_video",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([&](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
}

MediaKitVideoPlugin::~MediaKitVideoPlugin() {
  if (flutter_window_ && original_window_proc_) {
    ::SetWindowLongPtr(flutter_window_, GWLP_WNDPROC,
                       reinterpret_cast<LONG_PTR>(original_window_proc_));
  }
  if (instance_ == this) {
    instance_ = nullptr;
  }
}

void MediaKitVideoPlugin::RunOnMainThread(std::function<void()> task) {
  if (!flutter_window_) {
    return;
  }

  {
    std::lock_guard<std::mutex> lock(main_thread_tasks_mutex_);
    main_thread_tasks_.push(std::move(task));
  }

  ::PostMessage(flutter_window_, kMainThreadTaskMessage, 0, 0);
}

LRESULT CALLBACK MediaKitVideoPlugin::WindowProcDelegate(HWND hwnd,
                                                         UINT message,
                                                         WPARAM wParam,
                                                         LPARAM lParam) {
  if (message == kMainThreadTaskMessage && instance_) {
    instance_->ProcessMainThreadTasks();
    return 0;
  }

  if (instance_ && instance_->original_window_proc_) {
    return ::CallWindowProc(instance_->original_window_proc_, hwnd, message,
                            wParam, lParam);
  }

  return ::DefWindowProc(hwnd, message, wParam, lParam);
}

void MediaKitVideoPlugin::ProcessMainThreadTasks() {
  std::queue<std::function<void()>> tasks_to_execute;

  {
    std::lock_guard<std::mutex> lock(main_thread_tasks_mutex_);
    tasks_to_execute.swap(main_thread_tasks_);
  }

  while (!tasks_to_execute.empty()) {
    auto task = std::move(tasks_to_execute.front());
    tasks_to_execute.pop();

    try {
      task();
    } catch (...) {
    }
  }
}

void MediaKitVideoPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  // Cross-platform native-output contract. This backend remains fail-closed
  // until a verified D3D11 flip-model HDR surface is attached.
  if (method_call.method_name().compare("createNativeOutput") == 0 ||
      method_call.method_name().compare("configureHdrOutput") == 0 ||
      method_call.method_name().compare("resetHdrOutput") == 0) {
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("backend"), flutter::EncodableValue("d3d11-native-surface")},
        {flutter::EncodableValue("capable"), flutter::EncodableValue(false)},
        {flutter::EncodableValue("active"), flutter::EncodableValue(false)},
        {flutter::EncodableValue("failureReason"), flutter::EncodableValue("native HDR surface probe unavailable")},
        {flutter::EncodableValue("supportedInputFormats"), flutter::EncodableValue(std::vector<flutter::EncodableValue>{flutter::EncodableValue("sdr"), flutter::EncodableValue("hdr10"), flutter::EncodableValue("hlg")})},
        {flutter::EncodableValue("supportedOutputFormats"), flutter::EncodableValue(std::vector<flutter::EncodableValue>{})},
        {flutter::EncodableValue("sourceProcessing"), flutter::EncodableValue("tone-mapped")},
        {flutter::EncodableValue("outputEncoding"), flutter::EncodableValue("texture-sdr")},
        {flutter::EncodableValue("dynamicMetadataApplied"), flutter::EncodableValue(false)},
        {flutter::EncodableValue("pixelFormat"), flutter::EncodableValue("unknown")},
        {flutter::EncodableValue("colorSpace"), flutter::EncodableValue("sdr")},
        {flutter::EncodableValue("headroom"), flutter::EncodableValue(1.0)},
        {flutter::EncodableValue("generation"), flutter::EncodableValue(int64_t(0))},
    }));
  } else if (method_call.method_name().compare("disposeNativeOutput") == 0) {
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else if (method_call.method_name().compare("VideoOutputManager.Create") == 0) {
    auto arguments = std::get<flutter::EncodableMap>(*method_call.arguments());
    auto handle =
        std::get<std::string>(arguments[flutter::EncodableValue("handle")]);
    auto configuration = std::get<flutter::EncodableMap>(
        arguments[flutter::EncodableValue("configuration")]);

    auto handle_value = std::stoll(handle);
    auto configuration_value = VideoOutputConfiguration{};

    auto configuration_width =
        std::get<std::string>(configuration[flutter::EncodableValue("width")]);
    auto configuration_height =
        std::get<std::string>(configuration[flutter::EncodableValue("height")]);
    auto configuration_enable_hardware_acceleration = std::get<bool>(
        configuration[flutter::EncodableValue("enableHardwareAcceleration")]);
    if (configuration_width.compare("null") != 0) {
      configuration_value.width =
          static_cast<int64_t>(std::stoll(configuration_width.c_str()));
    }
    if (configuration_height.compare("null") != 0) {
      configuration_value.height =
          static_cast<int64_t>(std::stoll(configuration_height.c_str()));
    }
    configuration_value.enable_hardware_acceleration =
        configuration_enable_hardware_acceleration;

    video_output_manager_->Create(
        handle_value, configuration_value,
        [this, handle = handle_value](auto id, auto width, auto height) {
          RunOnMainThread([=]() {
            channel_->InvokeMethod(
                "VideoOutput.Resize",
                std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
                    {
                        flutter::EncodableValue("handle"),
                        flutter::EncodableValue(handle),
                    },
                    {
                        flutter::EncodableValue("id"),
                        flutter::EncodableValue(id),
                    },
                    {
                        flutter::EncodableValue("rect"),
                        flutter::EncodableValue(flutter::EncodableMap{
                            {
                                flutter::EncodableValue("left"),
                                flutter::EncodableValue(0),
                            },
                            {
                                flutter::EncodableValue("top"),
                                flutter::EncodableValue(0),
                            },
                            {
                                flutter::EncodableValue("width"),
                                flutter::EncodableValue(width),
                            },
                            {
                                flutter::EncodableValue("height"),
                                flutter::EncodableValue(height),
                            },
                        }),
                    },
                }),
                nullptr);
          });
        });
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else if (method_call.method_name().compare("VideoOutputManager.Dispose") ==
             0) {
    auto arguments = std::get<flutter::EncodableMap>(*method_call.arguments());
    auto handle =
        std::get<std::string>(arguments[flutter::EncodableValue("handle")]);
    auto handle_value = static_cast<int64_t>(std::stoll(handle.c_str()));
    video_output_manager_->Dispose(handle_value);
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else if (method_call.method_name().compare("VideoOutputManager.SetSize") ==
             0) {
    auto arguments = std::get<flutter::EncodableMap>(*method_call.arguments());
    auto handle =
        std::get<std::string>(arguments[flutter::EncodableValue("handle")]);
    auto width =
        std::get<std::string>(arguments[flutter::EncodableValue("width")]);
    auto height =
        std::get<std::string>(arguments[flutter::EncodableValue("height")]);
    auto handle_value = static_cast<int64_t>(std::stoll(handle.c_str()));
    auto width_value = std::optional<int64_t>{};
    auto height_value = std::optional<int64_t>{};
    if (width.compare("null") != 0) {
      width_value = static_cast<int64_t>(std::stoll(width.c_str()));
    }
    if (height.compare("null") != 0) {
      height_value = static_cast<int64_t>(std::stoll(height.c_str()));
    }
    video_output_manager_->SetSize(handle_value, width_value, height_value);
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else if (method_call.method_name().compare("Utils.EnterNativeFullscreen") ==
             0) {
    auto window =
        ::GetAncestor(registrar_->GetView()->GetNativeWindow(), GA_ROOT);
    Utils::EnterNativeFullscreen(window);
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else if (method_call.method_name().compare("Utils.ExitNativeFullscreen") ==
             0) {
    auto window =
        ::GetAncestor(registrar_->GetView()->GetNativeWindow(), GA_ROOT);
    Utils::ExitNativeFullscreen(window);
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else if (method_call.method_name().compare("VideoRouteCapabilities.Get") ==
             0) {
    result->Success(flutter::EncodableValue(
        BuildRouteCapabilitiesResult(method_call)));
  } else {
    result->NotImplemented();
  }
}

}  // namespace media_kit_video
