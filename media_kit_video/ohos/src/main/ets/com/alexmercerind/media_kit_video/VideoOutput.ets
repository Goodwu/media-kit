/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 *
 * Copyright © 2025 & onwards, Bao Han <erbws@foxmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */

import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import display from '@ohos.display';
import { SurfaceTextureEntry } from '@ohos/flutter_ohos';
import { TextureRegistry } from '@ohos/flutter_ohos';
import { SizeData } from './Utils';

const TAG = "VideoOutput";

export interface SurfaceSize {
  width: number;
  height: number;
}

export class VideoOutput {
  private id: number = 0;
  private wid: number = 0;
  private w: number = 0;
  private h: number = 0;
  private requestedW: number = 0;
  private requestedH: number = 0;
  private textureRegistry: TextureRegistry;
  private surfaceProducer: SurfaceTextureEntry;
  private disposed: boolean = false;
  private textureSuspended: boolean = false;

  constructor(textureRegistry: TextureRegistry, surfaceProducer: SurfaceTextureEntry) {
    this.surfaceProducer = surfaceProducer;
    this.textureRegistry = textureRegistry;
    this.id = this.surfaceProducer.getTextureId();
    this.wid = this.surfaceProducer.getSurfaceId();
    Log.i(TAG, `create: textureId=${this.id}, surfaceId=${this.wid}`);
    this.setSurfaceSize(1, 1, true);
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }

    try {
      Log.i(TAG, `dispose: textureId=${this.id}, surfaceId=${this.wid}`);
      if (!this.textureSuspended) {
        this.textureRegistry.unregisterTexture(this.id);
      }
      this.disposed = true;
      this.id = 0;
      this.wid = 0;
      this.w = 0;
      this.h = 0;
    } catch (e) {
      Log.e(TAG, `dispose: ${e}`);
    }
  }

  suspendTexture(): void {
    if (this.disposed || this.textureSuspended) return;
    try {
      Log.i(TAG, `suspendTexture: textureId=${this.id}`);
      this.textureRegistry.unregisterTexture(this.id);
      this.textureSuspended = true;
    } catch (e) {
      Log.e(TAG, `suspendTexture: ${e}`);
    }
  }

  resumeTexture(): void {
    if (this.disposed || !this.textureSuspended) return;
    try {
      const textureId = this.textureRegistry.getTextureId();
      this.surfaceProducer = this.textureRegistry.registerTexture(textureId);
      this.id = this.surfaceProducer.getTextureId();
      this.wid = this.surfaceProducer.getSurfaceId();
      this.textureSuspended = false;
      Log.i(TAG, `resumeTexture: textureId=${this.id}, surfaceId=${this.wid}`);
      this.setSurfaceSize(this.requestedW, this.requestedH, true);
    } catch (e) {
      Log.e(TAG, `resumeTexture: ${e}`);
    }
  }

  setSurfaceSize(width: number, height: number, force: boolean = false): SurfaceSize {
    try {
      if (!force && this.requestedW == width && this.requestedH == height) {
        return { width: this.w, height: this.h };
      }

      this.requestedW = width;
      this.requestedH = height;
      const size = this.fitToDisplay(width, height);
      this.w = size.width;
      this.h = size.height;
      if (!this.textureSuspended) {
        this.textureRegistry.setTextureBufferSize(this.id, this.w, this.h);
      }
      Log.i(TAG, `setSurfaceSize: requested=${width}x${height}, actual=${this.w}x${this.h}`);
      return { width: this.w, height: this.h };
    } catch (e) {
      Log.e(TAG, `setSurfaceSize error: ${e}`);
      return { width: this.w, height: this.h };
    }
  }

  private fitToDisplay(width: number, height: number): SurfaceSize {
    if (width <= 0 || height <= 0) {
      return { width: width, height: height };
    }

    try {
      const info = display.getDefaultDisplaySync();
      const displayWidth = Math.max(1, info.width);
      const displayHeight = Math.max(1, info.height);
      // The display dimensions already reflect the current device
      // orientation. Do not swap them based on the video orientation: on a
      // portrait phone that lets a landscape video exceed the real window
      // width, which makes an XComponent/native surface render only in the
      // upper-left portion of the Flutter layout.
      const scale = Math.min(
        1,
        displayWidth / width,
        displayHeight / height,
      );
      return {
        width: Math.max(1, Math.floor(width * scale)),
        height: Math.max(1, Math.floor(height * scale)),
      };
    } catch (e) {
      Log.i(TAG, `fitToDisplay failed, using requested size: ${e}`);
      return { width: width, height: height };
    }
  }

  getSizeData(handle: number): SizeData {
    return {
      handle: handle,
      id: this.id,
      wid: this.wid,
      rect: {
        left: 0,
        top: 0,
        width: this.w,
        height: this.h,
      },
    }
  }
}
