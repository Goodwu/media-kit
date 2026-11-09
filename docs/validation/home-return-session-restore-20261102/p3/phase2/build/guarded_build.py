# usage: python3 -I guarded_build.py <log> <manifest-out-dir> -- cmd...
# Runs cmd in its own session; every 3s re-hashes the watched source set; on any change kills the process group, exit 99.
import sys, os, hashlib, subprocess, time, signal, json
log, outdir = sys.argv[1], sys.argv[2]
cmd = sys.argv[sys.argv.index('--')+1:]
MK = '/Users/wuweiwei1/src/media-kit'; PP = '/Users/wuweiwei1/src/PiliPlus'
ROOTS = [f'{MK}/media_kit/lib', f'{MK}/media_kit_video/lib', f'{MK}/media_kit_video/android/src',
         f'{MK}/media_kit_video/pubspec.yaml', f'{MK}/media_kit/pubspec.yaml',
         f'{MK}/media_kit_hdr_lab/lib', f'{MK}/media_kit_hdr_lab/android/app/src', f'{MK}/media_kit_hdr_lab/pubspec.yaml',
         f'{MK}/libs/android', f'{MK}/tool/build-android-test.sh', f'{MK}/tool/build_android_native.py', f'{MK}/tool/verify_android_test_apk.py',
         f'{PP}/lib', f'{PP}/pubspec.yaml', f'{PP}/pubspec_overrides.yaml', f'{PP}/pubspec.lock', f'{PP}/android/app/src', f'{PP}/android/app/build.gradle.kts']
SKIP = ('/build/', '/.cxx/', '/.dart_tool/', '/.gradle/', '.DS_Store')
def manifest():
    m = {}
    for r in ROOTS:
        if os.path.isfile(r):
            files = [r]
        elif os.path.isdir(r):
            files = [os.path.join(dp, f) for dp, dn, fn in os.walk(r) for f in fn]
        else:
            continue
        for p in files:
            if any(s in p for s in SKIP): continue
            try: m[p] = hashlib.sha256(open(p, 'rb').read()).hexdigest()
            except FileNotFoundError: pass
    return m
base = manifest()
tag = os.path.basename(log).rsplit('.', 1)[0]
json.dump(base, open(os.path.join(outdir, f'{tag}-manifest-start.json'), 'w'), indent=0)
agg = hashlib.sha256(''.join(f'{k}\0{v}\n' for k, v in sorted(base.items())).encode()).hexdigest()
with open(log, 'a') as L:
    L.write(f'# guard: {len(base)} watched files, manifest sha256 {agg}\n# start {time.strftime("%F %T %z")}\n# cmd: {" ".join(cmd)}\n'); L.flush()
    p = subprocess.Popen(cmd, stdout=L, stderr=subprocess.STDOUT, start_new_session=True, cwd=MK)
    rc = None; checks = 0
    while rc is None:
        time.sleep(3); rc = p.poll(); now = manifest(); checks += 1
        if now != base:
            diff = sorted(set(k for k in set(base) | set(now) if base.get(k) != now.get(k)))
            try: os.killpg(p.pid, signal.SIGTERM)
            except ProcessLookupError: pass
            L.write(f'\n# GUARD ABORT {time.strftime("%F %T %z")}: source changed: {diff}\n'); L.flush()
            print('GUARD ABORT', diff); sys.exit(99)
    L.write(f'\n# exit {rc} {time.strftime("%F %T %z")} guard checks={checks} manifest unchanged sha256 {agg}\n')
print('exit', rc, 'checks', checks, 'manifest', agg); sys.exit(rc)
