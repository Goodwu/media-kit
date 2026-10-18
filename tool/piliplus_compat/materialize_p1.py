#!/usr/bin/env python3
"""One-shot, audited SDK API migration. Never reads or patches the app checkout.

The CI materializer commits the real SDK sources before the build matrix. The
marker prevents replay. Input blob guards and exact replacement counts fail
closed rather than modifying a concurrently changed implementation.
"""
from pathlib import Path
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
MARKER = ROOT / 'docs/plans/piliplus-p1-materialized.json'
BASE = '867c48afc84db408bb3d131345f4c7a6a3b5796b'
GUARDS = {
 'media_kit/lib/src/player/native/player/real.dart':'d88cd9c3c47e8132f120eb2e220f6fa79dcaf32c',
 'media_kit/lib/src/player/native/core/initializer.dart':'c1fd6ba92c4512940dcfd13767674b35fb1e3f19',
 'media_kit/lib/src/models/player_state.dart':'1223c0f6119b8a7298a29511fea29c716e3f4c64',
 'media_kit/lib/src/models/player_stream.dart':'2eac0d5e6a827e91860e59105e11104cf7ec812b',
 'media_kit_video/lib/src/video_controller/platform_video_controller.dart':'b5d7e1fb3103bde4f32f7a5d228540a86ec73ed5',
}

def git(*args):
    return subprocess.check_output(['git','-C',str(ROOT),*args]).decode().strip()

def replace(text, old, new, count=1):
    if text.count(old) != count:
        raise RuntimeError(f'Expected {count} exact matches, got {text.count(old)}: {old[:120]!r}')
    return text.replace(old,new)

RENAMES = {'getProperty':'getPropertyAsync', 'Initializer':'PlayerInitializer',
           'screenshot':'screenshotBytes', 'mpv':'mpvBindings'}

def migrate_dart(text):
    """Rename Dart code identifiers, including interpolation, not literals/comments."""
    i = 0
    def changed(chunk):
        chunk = re.sub(r'\bstate\.(width|height)\b',
                       lambda m: 'state.video' + m[1].capitalize(), chunk)
        return re.sub(r'\b[A-Za-z_$][\w$]*\b', lambda m: RENAMES.get(m[0],m[0]),chunk)
    def code(end_brace=False):
        nonlocal i
        out=[]; buf=[]; depth=0
        def flush():
            if buf: out.append(changed(''.join(buf)));buf.clear()
        while i<len(text):
            if text.startswith('//',i):
                flush(); end=text.find('\n',i)
                if end<0: end=len(text)
                out.append(text[i:end]);i=end;continue
            if text.startswith('/*',i):
                flush();start=i;i+=2;nest=1
                while nest and i<len(text):
                    if text.startswith('/*',i):nest+=1;i+=2
                    elif text.startswith('*/',i):nest-=1;i+=2
                    else:i+=1
                if nest: raise RuntimeError('Unclosed Dart comment')
                out.append(text[start:i]);continue
            raw=text[i:i+1]=='r' and text[i+1:i+2] in ('"',"'")
            if text[i] in ('"',"'") or raw:
                flush();start=i
                if raw:i+=1
                quote=text[i]; delimiter=quote*3 if text.startswith(quote*3,i) else quote
                i+=len(delimiter);out.append(text[start:i])
                while i<len(text):
                    if text.startswith(delimiter,i):out.append(delimiter);i+=len(delimiter);break
                    if not raw and text[i]=='\\':out.append(text[i:i+2]);i+=2;continue
                    if not raw and text.startswith('${',i):
                        out.append('${');i+=2;out.append(code(True));continue
                    if not raw and text[i]=='$':
                        m=re.match(r'\$([A-Za-z_]\w*)',text[i:])
                        if m:out.append('$'+RENAMES.get(m[1],m[1]));i+=len(m[0]);continue
                    out.append(text[i]);i+=1
                else:raise RuntimeError('Unclosed Dart string')
                continue
            if end_brace:
                if text[i]=='{':depth+=1
                elif text[i]=='}':
                    if depth==0:
                        flush();out.append('}');i+=1;return ''.join(out)
                    depth-=1
            buf.append(text[i]);i+=1
        flush()
        if end_brace:raise RuntimeError('Unclosed interpolation')
        return ''.join(out)
    return code()


def main():
    if MARKER.exists():
        value=json.loads(MARKER.read_text())
        if value.get('migration')!='typed-player-p1' or value.get('base')!=BASE:
            raise RuntimeError('Unexpected migration marker')
        print('SDK P1 already materialized; no replay')
        return
    for path,blob in GUARDS.items():
        if git('hash-object',path)!=blob:raise RuntimeError('Source guard failed: '+path)
    changed=[]
    old_utf=ROOT/'media_kit/lib/ffi/src/utf8.dart'
    new_utf=ROOT/'media_kit/lib/ffi/src/utf8_core.dart'
    if new_utf.exists():raise RuntimeError('Unexpected utf8_core target')
    new_utf.write_bytes(old_utf.read_bytes())
    changed.append(str(new_utf.relative_to(ROOT)))
    roots=('media_kit/','media_kit_video/','media_kit_test/','media_kit_hdr_lab/','video_player_media_kit/')
    exclude=('media_kit/lib/src/compat/', 'media_kit_video/test/piliplus_player_contract_test.dart',
             'media_kit_video/test/legacy_mpv_native_test.dart',
             'media_kit/lib/src/player/native/core/legacy_mpv.dart')
    for relative in git('ls-files','*.dart').splitlines():
        if not relative.startswith(roots) or relative.startswith(exclude):continue
        path=ROOT/relative; old=path.read_text();new=migrate_dart(old)
        new=new.replace('ffi/src/utf8.dart','ffi/src/utf8_core.dart')
        if relative=='media_kit/lib/ffi/ffi.dart':
            new=new.replace("'src/utf8.dart'","'src/utf8_core.dart'")
        if new!=old:path.write_text(new);changed.append(relative)
    old_utf.write_text((ROOT/'tool/piliplus_compat/legacy_utf8_entrypoint.dart.txt').read_text())
    changed.append(str(old_utf.relative_to(ROOT)))

    p=ROOT/'media_kit/lib/src/models/player_state.dart';s=p.read_text()
    s=replace(s,'final int? width;', 'final int? videoWidth;\n\n  /// Legacy display size; unknown is zero, not evidence of a decoded frame.\n  int get width => videoWidth ?? 0;')
    s=replace(s,'final int? height;', 'final int? videoHeight;\n  int get height => videoHeight ?? 0;')
    start=s.index('  const PlayerState({');end=s.index('  PlayerState copyWith',start)
    ctor=s[start:end]
    ctor=replace(ctor,'this.width,','int? width,')
    ctor=replace(ctor,'this.height,','int? height,')
    ctor=replace(ctor,'});','}) : videoWidth = width, videoHeight = height;')
    s=s[:start]+ctor+s[end:]
    s=s.replace('this.width','videoWidth').replace('this.height','videoHeight')
    p.write_text(s)

    p=ROOT/'media_kit/lib/src/models/player_stream.dart';s=p.read_text()
    s="import '../compat/legacy_dimensions.dart';\n"+s
    s=replace(s,'class PlayerStream {','class PlayerStream {\n  /// Paired legacy size stream, with zero for unknown dimensions.\n  Stream<(int, int)> get size => legacyDimensions(width, height);\n')
    p.write_text(s)

    p=ROOT/'media_kit/lib/media_kit.dart';s=p.read_text()
    s+="\nexport 'src/compat/screenshot_bytes.dart'\n    if (dart.library.ui) 'src/compat/screenshot_flutter.dart';\n"
    p.write_text(s)

    p=ROOT/'media_kit/lib/src/player/native/core/initializer.dart';s=p.read_text()
    s="export 'legacy_mpv.dart' show Initializer;\n"+s
    p.write_text(s)

    p=ROOT/'media_kit/lib/src/player/native/player/real.dart';s=p.read_text()
    s="import '../core/legacy_mpv.dart' show LegacyMpv;\n"+s
    s=replace(s,'class NativePlayer extends PlatformPlayer {', '''class NativePlayer extends PlatformPlayer {
  /// Static legacy encoding ABI. Playback continues to use mpvBindings.
  static LegacyMpv get mpv => LegacyMpv.instance;
  static int get apiVersion => mpv.apiVersion;
  static void setHeader(LegacyMpv api, Pointer<generated.mpv_handle> handle,
      {String? userAgent, String? referer}) =>
      api.setHeader(handle, userAgent: userAgent, referer: referer);

  final Map<String, String> _legacyHttpHeaders = {};
  String _legacyHwdecCurrent = '';

  /// Synchronous application-level defaults: the next on_load observes these
  /// even when the caller does not await a property write. Per-media headers win.
  void setMediaHeader({String? userAgent, String? referer}) {
    if (disposed || isDisposing) throw StateError('Player is disposed');
    for (final entry in {'user-agent': userAgent, 'referer': referer}.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value.contains(RegExp(r'[\\r\\n\\x00]'))) throw ArgumentError('Invalid HTTP header');
      _legacyHttpHeaders[entry.key] = value;
    }
  }

  /// UI-only observed snapshots. Routing/lifetime decisions MUST use
  /// getPropertyAsync, never these synchronous compatibility values.
  String getProperty(String property) {
    if (disposed || isDisposing) throw StateError('Player is disposed');
    switch (property) {
      case 'volume': return state.volume.toString();
      case 'speed': return state.rate.toString();
      case 'pause': return state.playing ? 'no' : 'yes';
      case 'hwdec-current': return _legacyHwdecCurrent;
      default: throw UnsupportedError('Use getPropertyAsync for $property');
    }
  }
''')
    s=replace(s,'  Future<void> _handler(Pointer<generated.mpv_event> event) async {', '''  Future<void> _handler(Pointer<generated.mpv_event> event) async {
    if (event.ref.event_id == generated.mpv_event_id.MPV_EVENT_START_FILE ||
        event.ref.event_id == generated.mpv_event_id.MPV_EVENT_END_FILE) {
      _legacyHwdecCurrent = '';
    }
    if (event.ref.event_id == generated.mpv_event_id.MPV_EVENT_PROPERTY_CHANGE) {
      final observation = event.ref.data.cast<generated.mpv_event_property>().ref;
      if (observation.name.cast<Utf8>().toDartString() == 'hwdec-current') {
        final value = observation.format == generated.mpv_format.MPV_FORMAT_STRING &&
            observation.data != nullptr
            ? observation.data.cast<Pointer<Int8>>().value : nullptr.cast<Int8>();
        _legacyHwdecCurrent = value == nullptr ? '' : value.cast<Utf8>().toDartString();
      }
    }
''')
    s=replace(s,"        'pause': generated.mpv_format.MPV_FORMAT_FLAG,", "        'hwdec-current': generated.mpv_format.MPV_FORMAT_STRING,\n        'pause': generated.mpv_format.MPV_FORMAT_FLAG,")
    s=replace(s,'final headers = Media(uri).httpHeaders;', '''final headers = <String, String>{
            ..._legacyHttpHeaders,
            for (final entry in (Media(uri).httpHeaders ?? <String, String>{}).entries)
              entry.key.toLowerCase(): entry.value,
          };''')
    s=replace(s,'if (headers != null) {','if (headers.isNotEmpty) {')
    p.write_text(s)

    p=ROOT/'media_kit_video/lib/src/video_controller/platform_video_controller.dart';s=p.read_text()
    s=replace(s,'  final AndroidVideoOptions android;', '''  final AndroidVideoOptions _android;
  final bool? androidAttachSurfaceAfterVideoParameters;
  AndroidVideoOptions get android {
    final legacy = androidAttachSurfaceAfterVideoParameters;
    if (legacy == null) return _android;
    final current = _android.attachSurfaceAfterVideoParameters;
    if (current != null && current != legacy) {
      throw ArgumentError('Conflicting Android surface attachment options');
    }
    return _android.copyWith(attachSurfaceAfterVideoParameters: legacy);
  }''')
    s=replace(s,'    this.android = const AndroidVideoOptions(),', '    AndroidVideoOptions android = const AndroidVideoOptions(),\n    this.androidAttachSurfaceAfterVideoParameters,')
    s=replace(s,'    this.darwin = const DarwinVideoOptions(),\n  });', '    this.darwin = const DarwinVideoOptions(),\n  }) : _android = android;')
    p.write_text(s)

    p=ROOT/'media_kit_video/pubspec.yaml';s=p.read_text()
    s=replace(s,'sdk: ">=2.17.0 <4.0.0"','sdk: ">=3.1.0 <4.0.0"')
    p.write_text(s)
    changed=sorted(set(changed)|set(git('diff','--name-only').splitlines()))
    MARKER.write_text(json.dumps({'migration':'typed-player-p1','base':BASE,
        'changed':changed,'status':'materialized-not-yet-tested',
        'appSourceChanges':False,'automaticRouting':'not-yet-connected'},indent=2)+'\n')
    print(json.dumps({'changed':changed,'appModified':False},indent=2))

if __name__=='__main__':main()
