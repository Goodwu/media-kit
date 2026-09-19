/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 *
 * Copyright © 2025 & onwards, Bao Han <erbws@foxmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */

import deviceInfo from '@ohos.deviceInfo';
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class Utils {
  private static readonly kOrientationWaitMs: number = 5000;

  static isEmulator(): boolean {
    if (deviceInfo.productModel == "emulator") {
      return true;
    } else {
      return false;
    }
  }

  private static setPreferredOrientation(lastWindow: window.Window,
    orientation: window.Orientation): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      try {
        lastWindow.setPreferredOrientation(orientation, (error: BusinessError) => {
          if (error != undefined && error.code != 0) {
            reject(error);
            return;
          }
          resolve();
        });
      } catch (error) {
        reject(error);
      }
    });
  }

  private static async setPreferredOrientationAndWait(
    lastWindow: window.Window,
    orientation: window.Orientation,
    landscape: boolean,
    requestId: string,
  ): Promise<void> {
    await new Promise<void>((resolve, reject) => {
      let settled = false;
      let orientationSettled = false;
      let sizeMatched = false;
      let timeoutId: number | undefined;
      let onWindowSizeChange: (size: window.Size) => void;
      const finish = (error?: Error): void => {
        if (settled) return;
        settled = true;
        if (timeoutId != undefined) clearTimeout(timeoutId);
        lastWindow.off('windowSizeChange', onWindowSizeChange);
        if (error != undefined) {
          reject(error);
        } else {
          resolve();
        }
      };
      const completeIfReady = (): void => {
        if (orientationSettled && sizeMatched) finish();
      };
      onWindowSizeChange = (size: window.Size): void => {
        console.info(`[MediaKitVideo] fullscreen windowSizeChange ` +
          `requestId=${requestId} landscape=${landscape} ` +
          `width=${size.width} height=${size.height}`);
        sizeMatched = (size.width > size.height) == landscape;
        completeIfReady();
      };

      lastWindow.on('windowSizeChange', onWindowSizeChange);
      timeoutId = setTimeout(() => {
        const rect = lastWindow.getWindowProperties().windowRect;
        finish(new Error(
          `fullscreen orientation timeout: requestId=${requestId} ` +
          `expectedLandscape=${landscape} ` +
          `width=${rect.width} height=${rect.height}`,
        ));
      }, Utils.kOrientationWaitMs);

      // Subscribe before requesting the orientation. The system may emit the
      // resize event before setPreferredOrientation's completion callback.
      Utils.setPreferredOrientation(lastWindow, orientation).then(() => {
        orientationSettled = true;
        const rect = lastWindow.getWindowProperties().windowRect;
        console.info(`[MediaKitVideo] fullscreen orientation request settled ` +
          `requestId=${requestId} landscape=${landscape} ` +
          `width=${rect.width} height=${rect.height}`);
        sizeMatched = (rect.width > rect.height) == landscape;
        completeIfReady();
      }).catch((error: Error) => finish(error));
    });
  }

  static async enterFullScreen(
    context: common.UIAbilityContext,
    landscape: boolean = true,
    requestId: string = "none",
  ): Promise<void> {
    console.info(`[MediaKitVideo] enterFullScreen begin requestId=${requestId} landscape=${landscape}`);
    const lastWindow = await window.getLastWindow(context);
    const beforeRect = lastWindow.getWindowProperties().windowRect;
    console.info(`[MediaKitVideo] enterFullScreen window-ready requestId=${requestId} ` +
      `width=${beforeRect.width} height=${beforeRect.height}`);
    if (deviceInfo.deviceType == '2in1') {
      await lastWindow.maximize();
      console.info(`[MediaKitVideo] enterFullScreen committed requestId=${requestId} 2in1`);
      return;
    }
    if (landscape) {
      await lastWindow.enableLandscapeMultiWindow();
    } else {
      await lastWindow.disableLandscapeMultiWindow();
    }
    await Utils.setPreferredOrientationAndWait(
      lastWindow,
      landscape
        ? window.Orientation.USER_ROTATION_LANDSCAPE
        : window.Orientation.USER_ROTATION_PORTRAIT,
      landscape,
      requestId,
    );
    await lastWindow.setWindowSystemBarEnable([]);
    console.info(
      `[MediaKitVideo] enterFullScreen committed requestId=${requestId} ` +
      `${landscape ? 'landscape' : 'portrait'}`,
    );
  }

  static async exitFullScreen(
    context: common.UIAbilityContext,
    allowLandscape: boolean = false,
    requestId: string = "none",
  ): Promise<void> {
    console.info(`[MediaKitVideo] exitFullScreen begin requestId=${requestId} ` +
      `allowLandscape=${allowLandscape}`);
    const lastWindow = await window.getLastWindow(context);
    if (deviceInfo.deviceType == '2in1') {
      await lastWindow.recover();
      console.info(`[MediaKitVideo] exitFullScreen committed requestId=${requestId} 2in1`);
      return;
    }
    await lastWindow.disableLandscapeMultiWindow();
    if (deviceInfo.deviceType == 'phone') {
      // AUTO_ROTATION intentionally has no fixed portrait completion
      // condition: the user may leave fullscreen while holding the phone in
      // landscape. Only the explicit portrait request is verified here.
      if (allowLandscape) {
        await Utils.setPreferredOrientation(
          lastWindow,
          window.Orientation.AUTO_ROTATION,
        );
      } else {
        await Utils.setPreferredOrientationAndWait(
          lastWindow,
          window.Orientation.USER_ROTATION_PORTRAIT,
          false,
          requestId,
        );
      }
    }
    await lastWindow.setWindowSystemBarEnable(['status']);
    const afterRect = lastWindow.getWindowProperties().windowRect;
    console.info(`[MediaKitVideo] exitFullScreen committed requestId=${requestId} portrait ` +
      `width=${afterRect.width} height=${afterRect.height}`);
  }
}

export interface Rect {
  left: number,
  top: number,
  width: number,
  height: number,
}

export interface SizeData {
  handle: number,
  id: number,
  wid: number,
  rect: Rect,
}
