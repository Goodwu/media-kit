import MethodChannel from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import StandardMessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMessageCodec';
import PlatformView from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import PlatformViewFactory from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformViewFactory';
import common from '@ohos.app.ability.common';

declare class Params {
  direction: Direction;
  platformView: PlatformView;
}

const TAG = 'OhosNativeSurface';
export const OHOS_NATIVE_SURFACE_VIEW_TYPE =
  'com.alexmercerind/media_kit_video/ohos_native_surface';

export class OhosNativeSurfaceView extends PlatformView {
  readonly viewId: number;
  readonly handle: number;
  readonly controller: XComponentController = new XComponentController();
  private readonly events: MethodChannel;
  private disposed: boolean = false;

  constructor(viewId: number, handle: number, events: MethodChannel) {
    super();
    this.viewId = viewId;
    this.handle = handle;
    this.events = events;
  }

  getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(OhosNativeSurfaceBuilder);
  }

  onLoad(): void {
    if (this.disposed) {
      return;
    }
    const surfaceId = this.controller.getXComponentSurfaceId();
    console.info(`[${TAG}] onLoad view=${this.viewId} handle=${this.handle} surface=${surfaceId}`);
    this.events.invokeMethod('nativeSurfaceReady', {
      viewId: this.viewId,
      handle: this.handle,
      surfaceId: surfaceId,
    });
  }

  onDestroy(): void {
    this.disposed = true;
    console.info(`[${TAG}] onDestroy view=${this.viewId} handle=${this.handle}`);
    this.events.invokeMethod('nativeSurfaceDestroyed', {
      viewId: this.viewId,
      handle: this.handle,
    });
  }

  dispose(): void {
    this.disposed = true;
  }
}

@Component
struct OhosNativeSurfaceWidget {
  @Prop params: Params;
  view: OhosNativeSurfaceView =
    this.params.platformView as OhosNativeSurfaceView;

  build() {
    XComponent({
      id: `media_kit_ohos_native_surface_${this.view.viewId}`,
      type: XComponentType.SURFACE,
      controller: this.view.controller,
    })
      .onLoad(() => this.view.onLoad())
      .onDestroy(() => this.view.onDestroy())
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      // The Flutter player owns all playback gestures and control buttons.
      // Keep the native video surface out of ArkUI hit testing so its full
      // XComponent bounds do not swallow taps meant for the Flutter overlay.
      .hitTestBehavior(HitTestMode.None)
      .renderFit(RenderFit.RESIZE_FILL);
  }
}

@Builder
export function OhosNativeSurfaceBuilder(params: Params) {
  OhosNativeSurfaceWidget({
    params: params,
    view: params.platformView as OhosNativeSurfaceView,
  });
}

export class OhosNativeSurfaceFactory extends PlatformViewFactory {
  private readonly events: MethodChannel;

  constructor(events: MethodChannel) {
    super(StandardMessageCodec.INSTANCE);
    this.events = events;
  }

  create(context: common.Context, viewId: number, args: ESObject): PlatformView {
    console.info(`[${TAG}] create view=${viewId} args=${JSON.stringify(args)}`);
    // StandardMessageCodec decodes Flutter maps as ArkTS Map instances.
    // Reading the payload as a JS object makes `handle` undefined and causes
    // every native surface creation to fail before the XComponent is loaded.
    const values = args as Map<string, number>;
    const handle: number = values.get('handle') as number;
    if (!Number.isFinite(handle) || handle < 0) {
      throw new Error('OHOS native surface requires a valid player handle');
    }
    return new OhosNativeSurfaceView(viewId, handle, this.events);
  }
}
