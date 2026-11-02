#!/usr/bin/env python3
"""Build only the standalone API24 raw-YUV diagnostic; never deploy/run it."""
from pathlib import Path
import argparse,datetime,hashlib,json,os,subprocess

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 root=Path(__file__).resolve().parents[1]
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--output',type=Path)
 p.add_argument('--ndk',type=Path,default=Path.home()/'Library/Android/sdk/ndk/27.2.12479018')
 a=p.parse_args();stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
 out=(a.output or root/'build'/f'lg-yuv-fusion-{stamp}-{os.getpid()}').resolve();out.mkdir(parents=True,exist_ok=False)
 source=root/'tool/native/lg_yuv_fusion_probe.c';builder=Path(__file__).resolve();ndk=a.ndk.resolve(strict=True)
 if '27.2.12479018' not in (ndk/'source.properties').read_text():raise SystemExit('NDK27.2 required')
 bins=ndk/'toolchains/llvm/prebuilt/darwin-x86_64/bin';cc=bins/'aarch64-linux-android24-clang';binary=out/'lg_yuv_fusion_probe'
 command=[str(cc),'-std=c11','-O2','-Wall','-Wextra','-Werror','-fPIE','-pie','-Wl,--build-id=sha1',str(source),'-lEGL','-lGLESv3','-landroid','-lmediandk','-o',str(binary)]
 receipt={'schema':1,'status':'building','source':str(source),'sourceSha256':sha(source),'builderSha256':sha(builder),'compilerSha256':sha((bins/'clang').resolve()),'command':command,'createdAtUTC':stamp,'scope':'API24 ImageReader offscreen YUV A/B synthetic byte equality only, no playback/panel or performance claim'}
 def save(): (out/'build-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
 save()
 try:
  r=subprocess.run(command,capture_output=True,text=True);(out/'build.stdout').write_text(r.stdout);(out/'build.stderr').write_text(r.stderr)
  if r.returncode:raise RuntimeError(f'clang exit {r.returncode}')
  r=subprocess.run([str(bins/'llvm-readelf'),'-h','-d',str(binary)],capture_output=True,text=True,check=True);(out/'elf.txt').write_text(r.stdout)
  if not all(t in r.stdout for t in ['AArch64','ELF64','DYN']):raise RuntimeError('ELF must be arm64 PIE')
  if sha(source)!=receipt['sourceSha256'] or sha(builder)!=receipt['builderSha256']:raise RuntimeError('source drift')
  receipt.update(status='built-not-run',binary=str(binary),binarySha256=sha(binary),binaryBytes=binary.stat().st_size)
  save();print(json.dumps(receipt));return 0
 except Exception as e:
  receipt.update(status='build-failed',error=str(e));save();raise
if __name__=='__main__':raise SystemExit(main())
