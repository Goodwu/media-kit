/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// The application uses the pre-1.2 public API where `Player` is the native
/// player implementation. Keep this alias while the fork carries newer
/// platform backends internally.
export 'player_native.dart'
    if (dart.library.html) 'player_web.dart';
