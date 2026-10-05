# Shared gpu-next core candidate

This directory preserves the complete mpv 0.41.0 shared-core patch, including
frame metadata, hardware-frame import, target policy, renderer and both native
VO/libmpv adapters. Android and macOS must consume the same prepared source;
platform decoding, texture import and presentation remain adapters.

Prepare a fresh source directory:

```sh
python3 tool/shared_gpu_next/prepare.py /path/to/mpv.tar.gz /new/source/directory
```

The preparer checks the baseline archive, patch, original files and every
modified output file against `manifest.json`. It refuses an existing output.
The pinned dependencies for the current candidate are libplacebo 7.349 and the
reviewed FFmpeg 9.0.1 runtime; they must match the compiled headers and each ABI.

The macOS bridge selects `opengl-next` when the signed application plist sets
`MediaKitSharedRenderer=true`, or when `MEDIA_KIT_SHARED_RENDERER=1` is set for
a local experiment. A candidate bundle must explicitly carry the plist choice. It passes the private v1 target/diagnostics
contract without importing libplacebo layouts. A missing backend or failed
render is a failure, never permission to silently fall back for P5.

This remains a candidate. Source hashes, build success, ABI tests and backend
creation do not prove DV color, display brightness or playback smoothness.
Universal package loading, real rendering, Android regression, visible P5/HDR
acceptance and final product lifecycle tests remain required before delivery.

`build_macos.py` provides the candidate arm64/x86_64 build path. It requires
explicit archive, work/output directories and reviewed dependency inputs;
it does not choose a temporary checkout or change an application by default.
Dependency configuration is JSON with `schema_version: 1` and an
`architectures` object containing `arm64` and `x86_64` entries. Each entry
requires these absolute paths:

| Field | Input |
| --- | --- |
| `prefix` | Matching ABI prefix containing libplacebo API349 headers |
| `vulkan_include` | Include directory containing `vulkan/vulkan_core.h` |
| `ffmpeg_include`, `ffmpeg_lib_dir` | Reviewed FFmpeg 9.0.1 headers and dylibs |
| `libass_include`, `libass_library` | Reviewed 0.17.1 headers and dylib |
| `uchardet_include`, `uchardet_library` | Reviewed uchardet headers and dylib |
| `libplacebo_library`, `vulkan_library` | Explicit reviewed dylibs for that ABI |

Required transitive dylibs/frameworks must resolve within these explicit
library directories. Inspect input hashes, header/runtime ABI versions and
each dependency's deployment target before treating the report as a lock:

```sh
python3 tool/shared_gpu_next/build_macos.py \
  --dependency-config /inputs/dependency-config.json \
  --inspect-dependencies /inputs/reviewed-dependency-lock.json

python3 tool/shared_gpu_next/build_macos.py \
  --archive /inputs/source/mpv.tar.gz \
  --work-dir /builds/shared-mpv-work \
  --output-dir /artifacts/shared-mpv-slices \
  --dependency-config /inputs/dependency-config.json \
  --dependency-lock /inputs/reviewed-dependency-lock.json
```

Fresh work/output must be absent and separate from repositories, dependency
inputs, the archive directory and applications. Both slices consume the same
complete source verified against the pinned archive plus patch. Builds disable
GPL, Lua, JavaScript and C plugins, target macOS 12 and reject Homebrew runtime
links or dependencies requiring a newer macOS. `--resume` verifies the complete
source, parameters, tools, dependencies and Meson state, then runs compilation
again. Published output is immutable; changed output requires fresh directories.

Both slices and the final input rechecks must succeed before the output
directory is published atomically. The output contains detailed
`slice-manifest.json` files and `approved-slices.json` (`arm64`/`x86_64` to SHA)
for the Pili candidate packager. These signed slices still use explicitly
locked external runtime directories in their RPATH; the manifests say
`external_runtime: true` and `portable_bundle: false`. The bundle packager must
copy/normalize/sign its runtime closure and perform its own loading gates.
This recipe does not enable a production default or establish playback/display
acceptance.
