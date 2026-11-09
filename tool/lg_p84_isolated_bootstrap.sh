#!/bin/bash -e
# LG P84 隔离构建 bootstrap：把隔离副本中的依赖按原配方 configure+build+install
# 到全新 prefix。命令参数逐条取自 buildscripts/{build.sh,scripts/*.sh}（见
# docs/validation/lg-p84-target-lease-20261105/isolated-build-bootstrap-20261108.md）。
# 不改依赖版本、不重打补丁、不下载；只写隔离树与隔离 prefix。
set -Eeuo pipefail

ISO=~/src/native-lgp84-isolated/libmpv-android-video-build-dv-experiment/buildscripts
NDK=~/Library/Android/sdk/ndk/27.2.12479018
JOBS="${MEDIA_KIT_BUILD_JOBS:-8}"
LOG="$ISO/bootstrap.log"
mkdir -p "$ISO"
exec > >(tee -a "$LOG") 2>&1

step() { echo; echo "=== [$(date +%H:%M:%S)] $* ==="; df -h ~ | tail -1 | awk '{print "disk avail:", $4}'; }

export ndk_triple=aarch64-linux-android
export CC=aarch64-linux-android26-clang
export CXX=aarch64-linux-android26-clang++
export AR=llvm-ar
export RANLIB=llvm-ranlib
export AS="$CC"
export LDFLAGS="-Wl,-O1,--icf=safe -Wl,-z,max-page-size=16384 -Wl,--build-id=sha1"
export PKG_CONFIG_SYSROOT_DIR="$ISO/prefix/arm64-v8a"
export PKG_CONFIG_LIBDIR="$PKG_CONFIG_SYSROOT_DIR/lib/pkgconfig"
unset PKG_CONFIG_PATH CPATH LIBRARY_PATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH || true
PATH="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
prefix_dir="$ISO/prefix/arm64-v8a"
cores=$JOBS
v_android_api=26

step "prefix 自符号链接（usr/local → .，与共享 prefix 布局一致）"
cd "$prefix_dir"
ln -sfn . usr
ln -sfn . local
ls -la "$prefix_dir"

step "shaderc：ndk-build（源=NDK 内置树，输出重定向到隔离 deps/shaderc）"
builddir="$ISO/deps/shaderc"
cd "$NDK/sources/third_party/shaderc"
"$NDK/ndk-build" -j"$cores" \
  NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=Android.mk \
  APP_PLATFORM=android-$v_android_api APP_STL=c++_shared APP_ABI=arm64-v8a \
  NDK_APP_OUT="$builddir" NDK_APP_LIBS_OUT="$builddir/libs" \
  libshaderc_combined
cd "$builddir"
mkdir -p "$prefix_dir/include" "$prefix_dir/lib/pkgconfig"
cp -r include/* "$prefix_dir/include"
cp libs/*/arm64-v8a/libshaderc.a "$prefix_dir/lib/libshaderc_combined.a"
mkdir -p "$prefix_dir"/lib/pkgconfig
cat >"$prefix_dir"/lib/pkgconfig/shaderc_combined.pc <<"END"
Name: shaderc_combined
Description:
Version: 2022.3-unknown
Libs: -L/usr/lib -lshaderc_combined
Cflags: -I/usr/include
END
echo "shaderc installed"

meson_dep() { # meson_dep <dep> <flags...>
  local dep=$1; shift
  step "$dep：meson setup + ninja + install"
  cd "$ISO/deps/$dep"
  env -u CC -u CXX meson setup _build-arm64 --prefix=/usr/local \
    --cross-file "$prefix_dir"/crossfile.txt "$@"
  ninja -C _build-arm64 -j"$cores"
  DESTDIR="$prefix_dir" ninja -C _build-arm64 install
}

meson_dep freetype
meson_dep fribidi -Dtests=false -Ddocs=false
meson_dep harfbuzz -Dtests=disabled -Ddocs=disabled
meson_dep lcms2 -Dtests=disabled
meson_dep dav1d -Denable_tests=false -Db_lto=true -Dstack_alignment=16

step "libxml2：autotools configure + make + install"
cd "$ISO/deps/libxml2"
mkdir -p _build-arm64
cd _build-arm64
../configure CFLAGS=-fPIC CXXFLAGS=-fPIC \
  --host=$ndk_triple \
  --disable-shared --enable-static --with-minimum --with-threads \
  --with-tree --without-lzma
make -j"$cores"
make DESTDIR="$prefix_dir" install

step "libass：autotools configure + make + install"
cd "$ISO/deps/libass"
mkdir -p _build-arm64
cd _build-arm64
../configure CFLAGS=-fPIC CXXFLAGS=-fPIC \
  --host=$ndk_triple \
  --with-pic --disable-asm --enable-static --disable-shared \
  --disable-require-system-font-provider
make -j"$cores"
make DESTDIR="$prefix_dir" install

step "mbedtls：make（源内构建，与 build_android_native 参数一致）"
cd "$ISO/deps/mbedtls"
make -j"$cores" 'CFLAGS=-fPIC -march=armv8-a+crypto' 'CXXFLAGS=-fPIC -march=armv8-a+crypto' no_test
make 'CFLAGS=-fPIC -march=armv8-a+crypto' 'CXXFLAGS=-fPIC -march=armv8-a+crypto' DESTDIR="$prefix_dir" install

step "ffmpeg：configure（原参数，prefix 指向隔离树）+ make + install"
cd "$ISO/deps/ffmpeg"
sed -i '' -e 's/#define FFMPEG_CONFIGURATION.*/#define FFMPEG_CONFIGURATION ""/' configure
mkdir -p _build-arm64
cd _build-arm64
../configure \
  --target-os=android --enable-cross-compile --cross-prefix=$ndk_triple- --ar=$AR --cc=$CC --ranlib=$RANLIB --nm=llvm-nm --strip=llvm-strip \
  --arch=aarch64 --cpu=armv8-a --pkg-config=pkg-config \
  --extra-cflags="-I$prefix_dir/include" --extra-ldflags="-L$prefix_dir/lib" \
  --disable-gpl --disable-nonfree --enable-version3 \
  --enable-static --disable-shared --disable-vulkan --disable-iconv \
  --pkg-config-flags=--static \
  --disable-muxers --disable-decoders --disable-encoders --disable-demuxers \
  --disable-parsers --disable-protocols --disable-devices --disable-filters \
  --disable-doc --disable-avdevice --disable-postproc --disable-programs \
  --disable-gray --disable-swscale-alpha \
  --enable-jni --enable-bsfs --enable-mediacodec \
  --disable-dxva2 --disable-vaapi --disable-vdpau \
  --disable-bzlib --disable-linux-perf --disable-videotoolbox --disable-audiotoolbox \
  --enable-small --enable-hwaccels --enable-optimizations --enable-runtime-cpudetect \
  --enable-mbedtls --enable-libdav1d --enable-libxml2 \
  --enable-avutil --enable-avcodec --enable-avfilter --enable-avformat \
  --enable-swscale --enable-swresample \
  --enable-decoder=flv --enable-decoder=h263 --enable-decoder=h263i --enable-decoder=h263p \
  --enable-decoder='h264*' --enable-decoder=mpeg1video --enable-decoder='mpeg2*' \
  --enable-decoder='mpeg4*' --enable-decoder=vp6 --enable-decoder=vp6a --enable-decoder=vp6f \
  --enable-decoder='vp8*' --enable-decoder='vp9*' --enable-decoder='hevc*' --enable-decoder='av1*' \
  --enable-decoder=libdav1d --enable-decoder=theora --enable-decoder='msmpeg*' \
  --enable-decoder='mjpeg*' --enable-decoder='wmv*' \
  --enable-decoder='aac*' --enable-decoder=ac3 --enable-decoder=alac --enable-decoder=als \
  --enable-decoder=ape --enable-decoder='atrac*' --enable-decoder=eac3 --enable-decoder=flac \
  --enable-decoder='gsm*' --enable-decoder=mp1* --enable-decoder=mp2* --enable-decoder='mp3*' \
  --enable-decoder='mpc*' --enable-decoder=opus --enable-decoder='ra*' --enable-decoder=ralf \
  --enable-decoder=shorten --enable-decoder=tak --enable-decoder=tta --enable-decoder=vorbis \
  --enable-decoder=wavpack --enable-decoder='wma*' --enable-decoder='pcm*' --enable-decoder='dsd*' \
  --enable-decoder=dca \
  --enable-decoder=ssa --enable-decoder=ass --enable-decoder=dvbsub --enable-decoder=dvdsub \
  --enable-decoder=srt --enable-decoder=stl --enable-decoder=subrip --enable-decoder=subviewer \
  --enable-decoder=subviewer1 --enable-decoder=text --enable-decoder=vplayer --enable-decoder=webvtt \
  --enable-decoder=movtext \
  --enable-demuxer=concat --enable-demuxer=data --enable-demuxer=flv --enable-demuxer=hls \
  --enable-demuxer=latm --enable-demuxer=live_flv --enable-demuxer=loas --enable-demuxer=m4v \
  --enable-demuxer=mov --enable-demuxer=mpegps --enable-demuxer=mpegts --enable-demuxer=mpegvideo \
  --enable-demuxer=hevc --enable-demuxer=rtsp --enable-demuxer=mpeg4 --enable-demuxer='mjpeg*' \
  --enable-demuxer=avi --enable-demuxer=av1 --enable-demuxer=matroska --enable-demuxer=dash \
  --enable-demuxer=webm_dash_manifest \
  --enable-demuxer=aac --enable-demuxer=ac3 --enable-demuxer=aiff --enable-demuxer=ape \
  --enable-demuxer=asf --enable-demuxer=au --enable-demuxer=avi --enable-demuxer=flac \
  --enable-demuxer=flv --enable-demuxer=matroska --enable-demuxer=mov --enable-demuxer=m4v \
  --enable-demuxer=mp3 --enable-demuxer='mpc*' --enable-demuxer=ogg --enable-demuxer='pcm*' \
  --enable-demuxer=rm --enable-demuxer=shorten --enable-demuxer=tak --enable-demuxer=tta \
  --enable-demuxer=wav --enable-demuxer=wv --enable-demuxer=xwma --enable-demuxer=dsf \
  --enable-demuxer=truehd --enable-demuxer=dts --enable-demuxer=dtshd \
  --enable-demuxer=ass --enable-demuxer=srt --enable-demuxer=stl --enable-demuxer=webvtt \
  --enable-demuxer=subviewer --enable-demuxer=subviewer1 --enable-demuxer=vplayer \
  --enable-parser=h263 --enable-parser=h264 --enable-parser=hevc --enable-parser=mpeg4 \
  --enable-parser=mpeg4video --enable-parser=mpegvideo \
  --enable-parser='aac*' --enable-parser=ac3 --enable-parser=cook --enable-parser=dca \
  --enable-parser=flac --enable-parser=gsm --enable-parser=mpegaudio --enable-parser=tak \
  --enable-parser=vorbis \
  --enable-filter=overlay --enable-filter=equalizer \
  --enable-protocol=async --enable-protocol=cache --enable-protocol=crypto --enable-protocol=data \
  --enable-protocol=ffrtmphttp --enable-protocol=file --enable-protocol=ftp --enable-protocol=hls \
  --enable-protocol=http --enable-protocol=httpproxy --enable-protocol=https --enable-protocol=pipe \
  --enable-protocol=rtmp --enable-protocol=rtmps --enable-protocol=rtmpt --enable-protocol=rtmpts \
  --enable-protocol=rtp --enable-protocol=subfile --enable-protocol=tcp --enable-protocol=tls \
  --enable-protocol=srt \
  --enable-encoder=mjpeg --enable-encoder=ljpeg --enable-encoder=jpegls \
  --enable-encoder=jpeg2000 --enable-encoder=png \
  --enable-network
make -j"$cores"
make DESTDIR="$prefix_dir" install

step "libplacebo：meson setup + ninja + install + .pc 附加 -lc++"
cd "$ISO/deps/libplacebo"
env -u CC -u CXX meson setup _build-arm64 --prefix=/usr/local \
  --cross-file "$prefix_dir"/crossfile.txt \
  -Dvulkan=enabled -Ddemos=false -Dshaderc=enabled -Dlcms=enabled
ninja -C _build-arm64 -j"$cores"
DESTDIR="$prefix_dir" ninja -C _build-arm64 install
sed -i '' '/^Libs:/ s|$| -lc++|' "$prefix_dir"/lib/pkgconfig/libplacebo.pc

step "bootstrap 完成：prefix 内容清点"
ls "$prefix_dir/lib/pkgconfig"
find "$prefix_dir/lib" -name '*.a' | sort
df -h ~ | tail -1 | awk '{print "disk avail:", $4}'
echo "BOOTSTRAP-OK"
