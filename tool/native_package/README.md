# Verified native packages

This opt-in interface lets a native build produce one complete development
package and lets application builds reuse it. A package contains the runtime,
the headers used for that runtime, and any link-time or bundled dependencies.
Native sources do not need to be rebuilt for every Flutter-only change.

Use the verifier from the **pinned media-kit source checkout**, not a script
shipped inside an untrusted download. Python 3.9 or later is required; only its
standard library is used. Existing release downloads remain the default when
none of the explicit package inputs is defined.

## Creating a package

The producer writes a metadata spec **outside** its payload directory:

```json
{
  "schema": 1,
  "kind": "media-kit-native-package",
  "platform": "linux",
  "architectures": ["x86_64"],
  "profile": "video-default",
  "identity": {
    "origin": "source",
    "sources": {
      "mpv": {
        "repository": "https://github.com/Goodwu/mpv",
        "commit": "REPLACE_WITH_THE_FULL_ACTUAL_COMMIT"
      }
    },
    "recipe": {"repository": "RECIPE_REPOSITORY", "commit": "ACTUAL_RECIPE_COMMIT"},
    "toolchain": {"name": "ACTUAL_TOOLCHAIN", "version": "ACTUAL_VERSION"},
    "options": {},
    "patches": []
  },
  "layout": {
    "include": "include",
    "runtime": "lib/libmpv.so.2",
    "bundle": ["lib/libmpv.so.2"]
  },
  "capabilities": [],
  "validation": {"compiled": true, "runtime": false, "device": false}
}
```

```sh
python3 tool/native_package/package.py create \
  --root /absolute/path/to/payload --spec /absolute/path/to/package-spec.json
```

`create` validates the layout, computes the complete inventory, and writes
`payload/manifest.json`. Its one-line JSON result contains `root`, `manifest`,
`manifest_sha256`, `identity_sha256`, and `platform`. An optional `--manifest`
selects another filename directly inside the payload root.

The fields `schema` and `kind` may be omitted from the input spec; their defaults
are the values above. Do not supply `files`, `symlinks`, or `identity_sha256` in
the spec. They are computed from the actual payload. An unrelated spec or
receipt placed inside the root becomes part of the authenticated inventory.

The identity describes actual inputs. For source builds, record full commits of
all native repositories, the recipe commit, patch hashes and order, compiler/SDK
versions, target API levels, and build options. For repackaged existing binaries,
use `origin: "upstream-binary"` and record the exact release asset URL and its
SHA256, known producing recipe/source references, and any unavailable provenance
explicitly. A successful download does not establish source reproducibility.

The manifest's identity hash is exactly:

```python
hashlib.sha256(json.dumps(identity, sort_keys=True, separators=(',', ':'),
                          ensure_ascii=False).encode('utf-8')).hexdigest()
```

The tool rejects non-finite numbers and duplicate JSON keys. It does not invent
capabilities or validation results. `compiled`, `runtime`, and `device` describe
separate completed checks. Set `runtime` or `device` to true only after the
corresponding test ran on the exact payload. Runtime extension support, such as
DXGI rendering parameters or custom HDR properties, cannot be inferred merely
from the presence of headers or a successful link.

## Platform layouts

All paths in a manifest are normalized relative POSIX paths within the package.
Every `include` points to a directory **containing `mpv/`**.

| Platform | Architectures | Required layout |
| --- | --- | --- |
| `android` | Android ABI names: `arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86` | `jars: { ABI: "runtime/file.jar" }`; optional `sdk_prefixes: { ABI: "sdk/ABI" }` |
| `windows` | `x86_64` or `arm64` | `include`, `import_library`, `runtime`, `bundle: [...]` |
| `linux` | `x86_64` or `arm64` | `include`, `runtime`, `bundle: [...]` |
| `ios` | `arm64`, optionally `x86_64` for simulators | `include`, `frameworks: ["Frameworks/Mpv.xcframework", ...]` |
| `macos` | `arm64`, `x86_64` as built | `include`, `frameworks: ["Frameworks/Mpv.xcframework", ...]` |
| `ohos` | `arm64` as built | `archive` and/or `runtime`; optional `include` |

Android JARs must each contain `lib/ABI/libmpv.so` and must not mix ABI directories
or contain duplicate/unsafe member names. The `jars` keys must exactly equal
`architectures`. A normal Android application build requires all four ABI JARs.
The existing `-PmediaKitArm64Only=true` setting permits an arm64-only package.
The verifier returns an absolute path and computed SHA256 for every JAR; Gradle
checks the copied JAR against that expected digest before it enters the build.
`sdk_prefixes` is available to producers that preserve headers, libraries, and
pkg-config metadata for further native development; Flutter does not link these
prefixes directly.

Windows requires `mpv/client.h`, `mpv/render.h`, and `mpv/render_dxgi.h` under the
include root, plus the matching import library and `libmpv-2.dll`. Linux requires
`client.h`, `render.h`, `render_gl.h`, and `libmpv.so.2`. The `bundle` list must
contain the selected runtime and every non-system runtime dependency selected
by the producer's dependency audit. Bundled files install side by side; their
basenames must be unique. A bundled symlink must target another basename in the
bundle list. This ensures that, for example, `libmpv.so.2 -> libmpv.so.2.5` has
its target installed too. Binary dependency closure and target ABI compatibility
still require native tooling and execution tests.

Apple packages require matching `client.h`, `render.h`, and `render_gl.h`, exactly
one `Mpv.xcframework`, and the remaining frameworks needed by that build. Each
framework's `Info.plist` must declare the selected platform and cover the
manifest's architectures. Use one combined slice per platform/variant, such as
`macos-arm64_x86_64` or `ios-arm64_x86_64-simulator`. The CocoaPods adapter creates
its framework search links from these declarations and copies headers from the
same authenticated package. Versioned framework symlinks are preserved only
when they remain inside their own XCFramework.

## Verification and consumption

The application orchestrator first verifies the **archive SHA256** from its
dependency lock, extracts the archive safely into a fresh directory, and then
verifies the expected manifest SHA256:

```sh
python3 tool/native_package/package.py verify \
  --root /absolute/path/to/payload \
  --manifest-sha256 ACTUAL_MANIFEST_SHA256 \
  --platform linux --architecture x86_64 \
  --expected-identity ACTUAL_IDENTITY_SHA256
```

`--architecture` and `--expected-identity` are optional extra checks. The latter
also accepts the spelling `--expected-identity-sha256`. Verification fails for
modified files, missing files, extra files, changed symlinks, unsafe paths,
dangling/escaping/recursive links, case-insensitive path collisions, a different
platform, or a different selected architecture. Empty directories are not part
of the inventory. The manifest itself is authenticated by its independently
expected digest, so it is excluded from `files`.

Symbolic-link targets use relative POSIX spelling in the manifest. On Windows,
native link separators are converted to `/` before recording or comparing this
spelling; drive-qualified, absolute, UNC, escaping and cyclic links are still
rejected. The verifier resolves each actual link before accepting it.

Export these values for the actual application build:

```sh
export MEDIA_KIT_NATIVE_PACKAGE_ROOT=/absolute/path/to/payload
export MEDIA_KIT_NATIVE_PACKAGE_MANIFEST=/absolute/path/to/payload/manifest.json
export MEDIA_KIT_NATIVE_PACKAGE_MANIFEST_SHA256=ACTUAL_MANIFEST_SHA256
```

`MANIFEST` is optional and defaults to `ROOT/manifest.json`. Defining **any** of
the three inputs selects the explicit path, even if the defined value is empty.
The root and manifest digest are then mandatory. A failure never selects a
release download or a previously extracted build cache. The optional
`MEDIA_KIT_NATIVE_PACKAGE_PYTHON` selects a Python executable when `python3` is
not available under that name.

The trusted `consume` subcommand reads those environment variables and uses the
same verification. CMake calls it with `--cmake OUTPUT` to obtain quoted absolute
paths. Android consumes its JSON output. Apple calls it from the existing
Makefiles with `--stage-frameworks OUTPUT` or `--stage-headers OUTPUT`. Generated
output must be separate from the immutable input package.

The integration currently covers the video packages used by PiliPlus. It is
intended for the media-kit source checkout; separately published pub packages
do not carry the monorepo verifier. On Linux, generic package inputs cannot be
combined with the older `MEDIA_KIT_ROUTING_MODE` receipt interface. On Android,
they cannot be combined with `mediaKitLocalArm64Jar`.

For Apple builds, the orchestrator must select **CocoaPods**. Swift Package
Manager retains its original pinned download behavior and does not implement
this external-package interface. OHOS retains its existing archive+SHA256
consumer: after verifying the generic package, the orchestrator supplies the
verified `archive` through `MEDIA_KIT_OHOS_LIBMPV_ARCHIVE` and its file SHA256
through `MEDIA_KIT_OHOS_LIBMPV_SHA256`.

A package has no application commit baked into its identity. Record the
application commit, media-kit commit, Flutter SDK commit/version, and selected
native manifest digest together in the final application build receipt.

## Contract checks

```sh
python3 -m unittest discover -s tool/native_package/tests -v
```

These tests exercise the trust boundary and adapters using small synthetic
payloads, including CMake and Make when installed. With `gradle` on `PATH`, or
`MEDIA_KIT_TEST_GRADLE` pointing to a Gradle executable, they also execute the
production Android acquisition block during real Gradle configuration. This
checks all four copied JARs and confirms a failed verifier preserves its exit
status and stderr without downloading fallback libraries. The explicit package
adapter uses `providers.exec`, which supports Gradle 7.5 and newer, including
Gradle 9 where `Project.exec` was removed.

These checks do not compile Flutter or Android plugins, decode video, establish
DXGI/HDR behavior, or validate a physical device.
