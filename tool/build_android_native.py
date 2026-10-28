#!/usr/bin/env python3
"""Build the local arm64 native source graph and package a fresh three-library JAR.

Uses configured dependency build trees, never a release JAR. Does not fetch,
checkout, patch or clean source repositories. Receipt records local revisions,
working bytes, actual archive inputs and build commands, not remote freshness.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import shlex
import subprocess
import sys
import zipfile

MESON = {'dav1d': 'src/libdav1d.a', 'freetype': 'libfreetype.a',
         'fribidi': 'lib/libfribidi.a', 'harfbuzz': 'src/libharfbuzz.a',
         'lcms2': 'src/liblcms2.a', 'libplacebo': 'src/libplacebo.a'}
MAKE = {'libxml2': '.libs/libxml2.a', 'libass': 'libass/.libs/libass.a'}
FFMPEG = ('avcodec', 'avfilter', 'avformat', 'avutil', 'swresample', 'swscale')
DEPS = ('mbedtls', 'shaderc', 'dav1d', 'freetype', 'fribidi', 'harfbuzz',
        'lcms2', 'libxml2', 'ffmpeg', 'libass', 'libplacebo')


def sha(path):
    path = Path(path)
    if not path.is_file():
        raise ValueError(f'missing file: {path}')
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def capture(argv, cwd=None):
    return subprocess.check_output(list(map(str, argv)), cwd=cwd).decode().strip()


def file_vector(root, paths):
    """Freeze bytes, file kinds and executable bits, including local additions."""
    rows = {}
    for name in sorted(set(paths)):
        path = root / name
        if path.is_symlink():
            rows[name] = {'link': os.readlink(path)}
        elif path.is_file():
            rows[name] = {'sha256': sha(path), 'executable': bool(path.stat().st_mode & 0o111)}
        elif not path.exists():
            rows[name] = {'deleted': True}
        else:
            raise ValueError(f'unsupported source file: {path}')
    return {'files': rows, 'sha256': hashlib.sha256(json.dumps(rows, sort_keys=True).encode()).hexdigest()}


def git_source(root):
    root = root.resolve(strict=True)
    if Path(capture(['git', '-C', root, 'rev-parse', '--show-toplevel'])).resolve() != root:
        raise ValueError(f'not an independent source checkout: {root}')
    # Build products untracked by upstream are not source inputs. Tracked files
    # are always included, even if their names look like build outputs.
    tracked = capture(['git', '-C', root, 'ls-files', '-z']).split('\0')
    extra = capture(['git', '-C', root, 'ls-files', '--others', '--exclude-standard', '-z']).split('\0')
    extra = [p for p in extra if not any(v.startswith(('_build', '.git')) for v in Path(p).parts)
             and Path(p).suffix not in ('.o', '.a', '.so', '.pyc')]
    names = [p for p in tracked + extra if p]
    submodules = {}
    for entry in capture(['git', '-C', root, 'ls-files', '--stage', '-z']).split('\0'):
        if not entry or not entry.startswith('160000 '):
            continue
        metadata, name = entry.split('\t', 1)
        expected = metadata.split()[1]
        names = [p for p in names if p != name]
        child = root / name
        initialized = (child / '.git').exists()
        submodules[name] = {'gitlink': expected, 'initialized': initialized}
        if initialized:
            submodules[name]['source'] = git_source(child)
        elif child.exists() and any(child.iterdir()):
            # A populated unregistered source directory cannot be called absent.
            submodules[name]['source'] = tree_source(child)
    return dict(file_vector(root, names), path=str(root),
                submodules=submodules, head=capture(['git', '-C', root, 'rev-parse', 'HEAD']),
                tree=capture(['git', '-C', root, 'rev-parse', 'HEAD^{tree}']),
                status=capture(['git', '-C', root, 'status', '--porcelain=v1', '--untracked-files=normal']),
                diffSha256=hashlib.sha256(subprocess.check_output(
                    ['git', '-C', str(root), 'diff', '--binary', '--no-ext-diff', 'HEAD', '--'])).hexdigest())


def tree_source(root):
    return dict(file_vector(root, [str(p.relative_to(root)) for p in root.rglob('*')
                                 if p.is_file() or p.is_symlink()]), path=str(root))


def archive_paths(ninja_text, search_dirs=()):
    """Read static inputs from the actual link edge; reject unresolved forms."""
    match = re.search(r'^build libmpv\.so:.*\n LINK_ARGS = (.*)$', ninja_text, re.M)
    if not match:
        raise ValueError('missing formal libmpv.so linker edge in build.ninja')
    args = shlex.split(match[1])
    directories = []
    index = 0
    while index < len(args):
        item = args[index]
        if item == '-L':
            index += 1
            if index >= len(args):
                raise ValueError('missing path after -L')
            directories.append(Path(args[index]))
        elif item.startswith('-L') and len(item) > 2:
            directories.append(Path(item[2:]))
        index += 1
    directories.extend(Path(p) for p in search_dirs)
    archives = set()
    static_only = False
    index = 0
    while index < len(args):
        item = args[index]
        if item in ('-Bstatic', '-Bdynamic'):
            static_only = item == '-Bstatic'
        elif item.startswith('@'):
            raise ValueError(f'unresolved linker response file: {item}')
        if item == '-Xlinker':
            raise ValueError(f'unresolved -Xlinker input: {args[index + 1] if index + 1 < len(args) else "<missing>"}')
        if item.endswith('.a'):
            path = Path(item)
            if not path.is_absolute():
                raise ValueError(f'unresolved relative linker archive: {item}')
            archives.add(str(path))
        elif item.startswith('-Wl,'):
            parts = item[4:].split(',')
            if any(part.startswith(('-l', '-L', '@')) or part.endswith('.a') for part in parts):
                raise ValueError(f'unresolved linker input option: {item}')
            for part in parts:
                if part in ('-Bstatic', '-Bdynamic'):
                    static_only = part == '-Bstatic'
        elif item == '-l' or (item.startswith('-l') and len(item) > 2):
            if item == '-l':
                index += 1
                if index >= len(args):
                    raise ValueError('missing library after -l')
                name = args[index]
            else:
                name = item[2:]
            suffixes = ('.a',) if static_only else ('.so', '.a')
            resolved = next((directory / f'lib{name}{suffix}'
                             for directory in directories for suffix in suffixes
                             if (directory / f'lib{name}{suffix}').is_file()), None)
            if resolved is None:
                raise ValueError(f'unresolved linker library: {item}')
            if resolved.suffix == '.a':
                archives.add(str(resolved))
        index += 1
    return sorted(archives)


def require_same(before, after):
    changed = [key for key in before if before[key] != after.get(key)]
    if set(before) != set(after) or changed:
        raise ValueError(f'source inputs changed during build: {changed}')


class Builder:
    def __init__(self, args):
        self.args = args
        self.repo = args.native_repo.resolve(strict=True)
        self.scripts = self.repo / 'buildscripts'
        self.deps = self.scripts / 'deps'
        self.prefix = self.scripts / 'prefix/arm64-v8a'
        self.mpv = args.mpv_source.resolve(strict=True)
        self.mpv_build = args.mpv_build.resolve(strict=True) if args.mpv_build else self.mpv / '_build-arm64-mks'
        self.ndk = args.ndk.resolve(strict=True)
        prebuilt = list((self.ndk / 'toolchains/llvm/prebuilt').glob('*'))
        if len(prebuilt) != 1:
            raise ValueError('NDK must contain one host toolchain')
        self.toolchain = prebuilt[0]
        self.bin = self.toolchain / 'bin'
        self.shader = self.ndk / 'sources/third_party/shaderc'
        self.output = args.output.resolve()
        self.output.mkdir(parents=True, exist_ok=False)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        CC='aarch64-linux-android26-clang', CXX='aarch64-linux-android26-clang++',
                        AR='llvm-ar', RANLIB='llvm-ranlib',
                        PKG_CONFIG_SYSROOT_DIR=str(self.prefix), PKG_CONFIG_LIBDIR=str(self.prefix / 'lib/pkgconfig'))
        self.env.pop('PKG_CONFIG_PATH', None)
        self.receipt = {'schemaVersion': 1, 'status': 'building', 'abi': 'arm64-v8a',
                        'sourcePolicy': 'current-local-checkouts-including-dirty-files',
                        'remoteFreshnessVerified': False, 'deviceVerified': False,
                        'commands': [], 'archives': {}, 'ndk': {'path': str(self.ndk),
                        'properties': (self.ndk / 'source.properties').read_text()},
                        'configuredBuildTreesReused': True}
        self.log = (self.output / 'build.log').open('w', buffering=1)

    def save(self):
        (self.output / 'native-candidate.json').write_text(json.dumps(self.receipt, indent=2, sort_keys=True) + '\n')

    def run(self, argv, cwd=None, env=None):
        argv = list(map(str, argv))
        row = {'argv': argv, 'cwd': str(cwd or self.scripts)}
        self.receipt['commands'].append(row)
        self.save()
        print('+', ' '.join(argv), flush=True)
        process = subprocess.Popen(argv, cwd=cwd or self.scripts, env=env or self.env,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for line in process.stdout:
            self.log.write(line)
            print(line, end='', flush=True)
        row['exitCode'] = process.wait()
        if row['exitCode']:
            raise subprocess.CalledProcessError(row['exitCode'], argv)

    def validate_configuration(self):
        compiler = capture([self.bin / 'aarch64-linux-android26-clang', '--version']).splitlines()[0]
        configured = {}
        # Incremental objects are tied to the configured NDK. Merely changing
        # PATH/CC does not make Make or Ninja rebuild old same-command objects.
        ninja = (self.mpv_build / 'build.ninja').read_text()
        ndk_inputs = re.findall(r'(/[^\s]+?)/toolchains/llvm/prebuilt/', ninja)
        if not ndk_inputs or any(Path(p).resolve() != self.ndk for p in ndk_inputs):
            raise ValueError('selected NDK differs from configured mpv NDK; use a separately configured source build tree')
        for name, root, build in [('mpv', self.mpv, self.mpv_build)] + [
                (name, self.deps / name, self.deps / name / '_build-arm64') for name in MESON]:
            info = json.loads((build / 'meson-info/meson-info.json').read_text())
            if Path(info['directories']['source']).resolve() != root.resolve() or Path(info['directories']['build']).resolve() != build.resolve():
                raise ValueError(f'configured build source directory mismatch: {name}')
            compilers = json.loads((build / 'meson-info/intro-compilers.json').read_text())['host']
            for language in ('c', 'cpp'):
                if language in compilers and compilers[language]['full_version'] != compiler:
                    raise ValueError(f'configured NDK compiler version mismatch: {name}/{language}; reconfigure a separate build tree')
            configured[name] = {'source': str(root.resolve()), 'build': str(build.resolve()), 'compilers': compilers}
        ffmpeg_build = self.deps / 'ffmpeg/_build-arm64'
        if (ffmpeg_build / 'src').resolve() != (self.deps / 'ffmpeg').resolve():
            raise ValueError('configured FFmpeg source mismatch')
        ffconfig = (ffmpeg_build / 'ffbuild/config.mak').read_text()
        if 'CC_IDENT=' + compiler not in ffconfig.splitlines():
            raise ValueError('configured FFmpeg NDK compiler version mismatch')
        for name in MAKE:
            build = self.deps / name / '_build-arm64'
            match = re.search(r'^top_srcdir = (.+)$', (build / 'Makefile').read_text(), re.M)
            if not match or (build / match[1]).resolve() != (self.deps / name).resolve():
                raise ValueError(f'configured Make source mismatch: {name}')
        self.receipt['configuredInputs'] = configured
        self.receipt['ndk']['compiler'] = compiler
        self.receipt['ndk']['tools'] = {name: {'path': str(self.bin / name), 'sha256': sha(self.bin / name)}
            for name in ('clang', 'ld.lld', 'llvm-ar', 'llvm-strip', 'llvm-readelf', 'llvm-nm')}

    def sources(self):
        result = {name: git_source(self.deps / name) for name in DEPS if name != 'shaderc'}
        result['mpv'] = git_source(self.mpv)
        result['helper'] = git_source(self.deps / 'media-kit-android-helper')
        result['shaderc-ndk-sources'] = tree_source(self.shader)
        files = ['build.sh', 'include/path.sh', 'include/depinfo.sh'] + [f'scripts/{n}.sh' for n in DEPS]
        files += ['scripts/package_native.py', 'scripts/weaken_undefined_imports.py']
        result['native-recipes'] = file_vector(self.scripts, files)
        result['builder'] = file_vector(Path(__file__).resolve().parent, [Path(__file__).name])
        result['ndk-tools'] = {name: sha(self.bin / name) for name in
            ('clang', 'ld.lld', 'llvm-ar', 'llvm-strip', 'llvm-readelf', 'llvm-nm')}
        return result

    def install_archive(self, source, name=None):
        destination = self.prefix / 'lib' / (name or source.name)
        if sha(source) != sha(destination):
            raise ValueError(f'installed archive does not match current build output: {source} -> {destination}')
        self.receipt['archives'][str(destination.resolve())] = {'buildOutput': str(source),
                                                               'sha256': sha(source)}

    def dependencies(self):
        jobs = str(self.args.jobs)
        for name in DEPS:
            root = self.deps / name
            build = root / '_build-arm64'
            if name == 'mbedtls':
                flags = ['CFLAGS=-fPIC -march=armv8-a+crypto', 'CXXFLAGS=-fPIC -march=armv8-a+crypto']
                self.run(['make', '-j' + jobs, *flags, 'no_test'], root)
                self.run(['make', *flags, 'DESTDIR=' + str(self.prefix), 'install'], root)
                for lib in ('mbedtls', 'mbedcrypto', 'mbedx509'):
                    self.install_archive(root / 'library' / f'lib{lib}.a')
            elif name == 'shaderc':
                self.run([self.ndk / 'ndk-build', '-j' + jobs, 'NDK_PROJECT_PATH=.', 'APP_BUILD_SCRIPT=Android.mk',
                          'APP_PLATFORM=android-26', 'APP_STL=c++_shared', 'APP_ABI=arm64-v8a',
                          'NDK_APP_OUT=' + str(root / 'local'), 'NDK_APP_LIBS_OUT=' + str(root / 'libs'),
                          'libshaderc_combined'], self.shader)
                archive = root / 'local/arm64-v8a/libshaderc_combined.a'
                shutil.copytree(self.shader / 'libshaderc/include', self.prefix / 'include', dirs_exist_ok=True)
                shutil.copy2(archive, self.prefix / 'lib/libshaderc_combined.a')
                self.install_archive(archive)
            elif name in MESON:
                self.run(['ninja', '-C', build, '-j', jobs])
                self.run(['ninja', '-C', build, 'install'], env=dict(self.env, DESTDIR=str(self.prefix)))
                self.install_archive(build / MESON[name])
            elif name in MAKE or name == 'ffmpeg':
                self.run(['make', '-C', build, '-j' + jobs])
                self.run(['make', '-C', build, 'DESTDIR=' + str(self.prefix), 'install'])
                if name == 'ffmpeg':
                    for lib in FFMPEG:
                        self.install_archive(build / f'lib{lib}/lib{lib}.a')
                else:
                    self.install_archive(build / MAKE[name])

    def build(self):
        try:
            self.validate_configuration()
            before = self.sources()
            self.receipt['sourcesBefore'] = before
            self.save()
            # Ensure all cached prefix inputs have an actual current build invocation.
            self.dependencies()
            options_path = self.mpv_build / 'meson-info/intro-buildoptions.json'
            options = json.loads(options_path.read_text())
            option_map = {item['name']: item['value'] for item in options}
            if option_map.get('buildtype') != 'release':
                raise ValueError('mpv configured buildtype must be release')
            link = option_map.get('c_link_args', [])
            if '-Wl,--build-id=sha1' not in link:
                # Formal Meson configuration; preserve existing arguments. No historical relink recipe.
                link.append('-Wl,--build-id=sha1')
                self.run(['meson', 'configure', self.mpv_build, '-Dc_link_args=' + ','.join(link)])
            self.run(['ninja', '-C', self.mpv_build, '-j', self.args.jobs])
            sysroot = self.toolchain / 'sysroot/usr/lib/aarch64-linux-android/26'
            clang_resources = self.bin / 'clang'  # resource path is obtained from this exact NDK compiler
            resource_dir = Path(capture([clang_resources, '--target=aarch64-linux-android26', '-print-resource-dir']))
            linked = archive_paths((self.mpv_build / 'build.ninja').read_text(), [
                sysroot, self.toolchain / 'sysroot/usr/lib/aarch64-linux-android',
                resource_dir / 'lib/linux/aarch64'])
            for path in linked:
                actual = str(Path(path).resolve())
                if actual not in self.receipt['archives']:
                    if not Path(actual).is_relative_to(self.ndk):
                        raise ValueError(f'unaccounted linker archive: {path}')
                    self.receipt['archives'][actual] = {'source': 'NDK toolchain runtime', 'sha256': sha(actual)}
            used = {str(Path(p).resolve()) for p in linked}
            if not set(self.receipt['archives']).issubset(used):
                raise ValueError('built archive set differs from the actual mpv linker inputs')
            self.receipt['mpvBuild'] = {'path': str(self.mpv_build), 'buildNinjaSha256': sha(self.mpv_build / 'build.ninja'),
                                       'options': json.loads(options_path.read_text()),
                                       'crossfile': (self.prefix / 'crossfile.txt').read_text()}
            stage = self.output / 'native'
            stage.mkdir()
            mpv = stage / 'libmpv.so'
            shutil.copy2(self.mpv_build / 'libmpv.so', mpv)
            self.run([self.bin / 'llvm-strip', '--strip-unneeded', mpv])
            helper = stage / 'libmediakitandroidhelper.so'
            cpp = self.deps / 'media-kit-android-helper/app/src/main/cpp'
            self.run([self.bin / 'aarch64-linux-android26-clang++', '-std=c++17', '-O2', '-fPIC', '-shared',
                      '-Wl,-soname,libmediakitandroidhelper.so', '-Wl,--build-id=sha1', '-Wl,-z,max-page-size=16384',
                      cpp / 'native-lib.cpp', '-llog', '-landroid', '-o', helper])
            self.run([self.bin / 'llvm-strip', '--strip-unneeded', helper])
            helper_apk = stage / 'helper-current.apk'
            with zipfile.ZipFile(helper_apk, 'x', zipfile.ZIP_DEFLATED) as archive:
                archive.write(helper, 'lib/arm64-v8a/libmediakitandroidhelper.so')
            libcxx = self.toolchain / 'sysroot/usr/lib/aarch64-linux-android/libc++_shared.so'
            self.receipt['libcxx'] = {'path': str(libcxx), 'sha256': sha(libcxx), 'source': 'selected NDK toolchain runtime'}
            nm = self.bin / 'llvm-nm'
            required = {mpv: ('mpv_create', 'mpv_initialize', 'mpv_lavc_set_java_vm', 'av_jni_set_java_vm'),
                        helper: ('MediaKitAndroidHelperGetJavaVM', 'MediaKitAndroidHelperOpenFileDescriptor',
                                 'Java_com_alexmercerind_mediakitandroidhelper_MediaKitAndroidHelper_setApplicationContextNative')}
            self.receipt['requiredSymbols'] = {}
            for library, names in required.items():
                defined = capture([nm, '-D', '--defined-only', library])
                symbols = {line.split()[-1] for line in defined.splitlines() if line.split()}
                if not set(names).issubset(symbols):
                    raise ValueError(f'missing Android/API exports in {library}: {set(names) - symbols}')
                self.receipt['requiredSymbols'][library.name] = list(names)
            self.run([sys.executable, self.scripts / 'scripts/package_native.py', '--mpv', mpv,
                      '--helper-apk', helper_apk, '--libcxx', libcxx, '--output', self.output / 'package',
                      '--abi', 'arm64-v8a', '--readelf', self.bin / 'llvm-readelf', '--nm', nm])
            after = self.sources()
            self.receipt['sourcesAfter'] = after
            require_same(before, after)
            # Freeze the final link input bytes again after packaging.
            for path, identity in self.receipt['archives'].items():
                if sha(path) != identity['sha256']:
                    raise ValueError(f'link input drifted: {path}')
            jar = self.output / 'package/default-arm64-v8a.jar'
            self.receipt.update(status='built-unreviewed', sourceDrift=False, jar=str(jar), jarSha256=sha(jar))
            print(f'JAR: {jar}', flush=True)
        except BaseException as error:
            self.receipt.update(status='failed', error=str(error))
            raise
        finally:
            self.save()
            self.log.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native-repo', type=Path, default=Path.home() / 'src/libmpv-android-video-build-dv-experiment')
    parser.add_argument('--mpv-source', type=Path, default=Path.home() / 'src/mpv')
    parser.add_argument('--mpv-build', type=Path)
    parser.add_argument('--ndk', type=Path, default=Path.home() / 'Library/Android/sdk/ndk/27.2.12479018')
    parser.add_argument('--jobs', type=int, default=4)
    parser.add_argument('--output', type=Path, required=True, help='fresh output directory; existing directories are rejected')
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error('--jobs must be positive')
    try:
        Builder(args).build()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        parser.exit(1, f'Native source build failed: {error}\n')


if __name__ == '__main__':
    main()
