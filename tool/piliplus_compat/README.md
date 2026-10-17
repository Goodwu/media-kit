# Unmodified PiliPlus: P0a dependency audit

This is the **first implementation slice**, not an application builder or an
HDR certification tool. It never edits either input checkout, fetches a branch,
invokes pub, or downloads a native binary. P0b isolated staging, complete input
freezing, application analysis/build, and device tests remain separate work.

## Run

Use clean Git checkouts of the **current development refs**. Fetch/resolve those
refs before each run; the recorded commit/tree identifies this run, not a fixed
old test baseline. Python 3.11+ and Git are required.

```sh
python3 -m pip install -r tool/piliplus_compat/requirements.txt
python3 tool/piliplus_compat/dependency_plan.py \
  --app-root /work/PiliPlus --sdk-root /work/media-kit \
  --out /work/receipts/dependency-plan-001
python3 -m unittest discover -s tool/piliplus_compat -p 'test_*.py' -v
```

Output must be a **new directory outside both inputs**. A `plan.json` records
source roots/commits/trees, manifest hashes, required packages, unresolved
packages and not-run stages. Only `declarations-ready` produces
`pubspec_overrides.yaml`. This means the declarations are audited, not that pub
or the application compiles. Exit code 2 is an audit failure; a missing package
produces a blocked plan, and other failures produce `failure.json` when the
output directory could safely be created. Existing outputs are never replaced.

The generated override file is for the exact app/SDK roots in that plan. Do not
copy it to another relocated app and assume relative non-player dependencies
remain correct. The future staging tool must generate it *after* relocation.
P0a does not install this file into the app. In a disposable checkout a caller
can install it as root `pubspec_overrides.yaml`, run pub, then check resolution:

```sh
python3 tool/piliplus_compat/dependency_plan.py \
  --verify-plan /work/receipts/dependency-plan-001/plan.json \
  --package-config /work/PiliPlus/.dart_tool/package_config.json \
  --out /work/receipts/resolution-001
```

Verification allows exactly app-root `pubspec.lock` and `pubspec_overrides.yaml`
as generated changes; the latter must equal the proposal. Other non-ignored
source changes and different source HEADs fail. Player roots and `packageUri`
must match the plan; duplicate, missing required and unplanned managed packages
fail. **This verifies paths, not solver execution, complete source/resource
integrity, native ABI, or binary freshness.** Ignored/generated inputs still
need P0b/P5 audits. No successful report promotes build/playback/HDR to passed.

## Deliberately conservative cases

An override-only package need not be reachable. It is recorded separately as
`unresolved-override-only`, not asserted to be a compiler failure. Resolve its
actual reachability before removing a stale override or implementing a real
compatibility package. Required missing packages are
`missing-required-package`. Neither case silently reuses an older fork or
creates an empty plugin.

Library roots are the current core/video/event-loop/video-player packages and
`libs/<platform>/<package>`. Applications, examples and tests are not candidate
SDK libraries. Root dependency/dev/override declarations and selected packages'
dependencies/federated default packages are audited; dependency-level dev and
override fields do not control the root resolution. Dependencies outside the
managed family still require pub and later provenance audits.

Duplicate/non-string YAML keys, anchors/aliases and Pub workspaces are rejected
until their semantics have dedicated support. A rejected input is not silently
rewritten. Preserve all non-player root overrides, including local path values.

The CI workflow is named **PiliPlus compatibility tools (T0 only)**. It runs the
fixture-based tool tests, not the original app. See the implementation plan in
`docs/plans/piliplus-zero-change-20261018.md` for the remaining gates.
