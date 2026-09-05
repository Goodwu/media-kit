/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 *
 * Copyright © 2025 & onwards, Bao Han <erbws@foxmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */

import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  AbilityAware,
  AbilityPluginBinding
} from '@ohos/flutter_ohos';
import { Utils } from './Utils';
import { VideoOutputManager } from './VideoOutputManager';
import { OhosNativeSurfaceFactory, OHOS_NATIVE_SURFACE_VIEW_TYPE } from './OhosNativeSurface';
import { common } from '@kit.AbilityKit';

export default class MediaKitVideoPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private videoOutputManager: VideoOutputManager | null = null;
  private nativeSurfaceEvents: MethodChannel | null = null;
  binding: FlutterPluginBinding | null = null;
  context: common.UIAbilityContext | null = null;

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.videoOutputManager = new VideoOutputManager(this.binding!.getTextureRegistry());
    this.context = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {
    this.videoOutputManager?.disposeAll();
    this.videoOutputManager = null;
    this.context = null;
  }

  getUniqueClassName(): string {
    return "MediaKitVideoPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "com.alexmercerind/media_kit_video");
    this.channel.setMethodCallHandler(this);
    this.nativeSurfaceEvents = new MethodChannel(
      binding.getBinaryMessenger(),
      "com.alexmercerind/media_kit_video/native_surface_events"
    );
    binding.getPlatformViewRegistry().registerViewFactory(
      OHOS_NATIVE_SURFACE_VIEW_TYPE,
      new OhosNativeSurfaceFactory(this.nativeSurfaceEvents)
    );
    this.binding = binding;
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
    }
    this.videoOutputManager?.disposeAll();
    this.videoOutputManager = null;
    this.nativeSurfaceEvents = null;
    this.channel = null;
    this.binding = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case "createNativeOutput":
      case "configureHdrOutput":
      case "resetHdrOutput": {
        result.success({
          backend: "ohos-native-window",
          capable: false,
          active: false,
          failureReason: "native HDR surface probe unavailable",
          generation: 0
        });
        break;
      }
      case "disposeNativeOutput": {
        result.success(null);
        break;
      }
      case "VideoOutputManager.Create": {
        const handle = parseInt(call.argument("handle"));
        if (this.videoOutputManager == null) {
          result.error("unavailable", "VideoOutputManager is not attached to an ability.", null);
          break;
        }
        result.success(this.videoOutputManager.create(handle));
        break;
      }
      case "VideoOutputManager.SetSurfaceSize": {
        const handle = parseInt(call.argument("handle"));
        const width = parseInt(call.argument("width"));
        const height = parseInt(call.argument("height"));
        const force = call.argument("force") === true;
        result.success(this.videoOutputManager?.setSurfaceSize(handle, width, height, force) ?? null);
        break;
      }
      case "VideoOutputManager.SuspendTexture": {
        const handle = parseInt(call.argument("handle"));
        this.videoOutputManager?.suspendTexture(handle);
        result.success(true);
        break;
      }
      case "VideoOutputManager.ResumeTexture": {
        const handle = parseInt(call.argument("handle"));
        result.success(this.videoOutputManager?.resumeTexture(handle) ?? null);
        break;
      }
      case "VideoOutputManager.Dispose": {
        const handle = parseInt(call.argument("handle"));
        this.videoOutputManager?.dispose(handle);
        result.success(null);
        break;
      }
      case "Utils.IsEmulator": {
        result.success(Utils.isEmulator());
        break;
      }
      case "Utils.EnterNativeFullscreen": {
        Utils.enterFullScreen(this.context!);
        result.success(null);
        break;
      }
      case "Utils.ExitNativeFullscreen": {
        Utils.exitFullScreen(this.context!);
        result.success(null);
        break;
      }
      default: {
        result.notImplemented();
        break;
      }
    }
  }
}
