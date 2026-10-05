#!/usr/bin/env python3
"""Content fingerprint for OHOS unsigned HAP artifacts.

Unzips a HAP and hashes every entry. Functional equivalence between two builds
is judged on KEY entries (native libs, Dart AOT artifacts, module descriptor);
byte-level ZIP noise (entry order/timestamps) is excluded by construction.

Usage:
  hap_fingerprint.py <a.hap> [b.hap]

With one HAP: prints a JSON fingerprint to stdout.
With two: compares them; exits non-zero if any KEY entry differs, prints a
human-readable diff (non-key drift is reported but does not fail).
"""
from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import zipfile
from pathlib import Path

# Entries whose equality is required for "functionally identical".
KEY_MATCHERS = (
    lambda n: n.startswith("libs/arm64-v8a/"),   # libflutter/libmpv/libapp/...
    lambda n: n == "ets/modules.abc",            # ArkTS bytecode
    lambda n: n == "module.json",
)

def is_key(name: str) -> bool:
    return any(m(name) for m in KEY_MATCHERS)

def fingerprint(hap: Path) -> dict:
    entries = {}
    with zipfile.ZipFile(hap) as z:
        for info in z.infolist():
            if info.is_dir():
                continue
            entries[info.filename] = hashlib.sha256(z.read(info)).hexdigest()
    key_names = sorted(n for n in entries if is_key(n))
    key_digest = hashlib.sha256(
        "\n".join(f"{n}={entries[n]}" for n in key_names).encode()
    ).hexdigest()
    return {
        "hap_sha256": hashlib.sha256(hap.read_bytes()).hexdigest(),
        "hap_name": hap.name,
        "entries": entries,
        "key_entries": key_names,
        "key_digest": key_digest,
    }

def compare(a: dict, b: dict) -> int:
    print(f"A: {a['hap_name']} hap={a['hap_sha256'][:16]}… key={a['key_digest'][:16]}…")
    print(f"B: {b['hap_name']} hap={b['hap_sha256'][:16]}… key={b['key_digest'][:16]}…")
    if a["key_digest"] == b["key_digest"]:
        print("VERDICT: key entries identical (functionally equivalent)")
    else:
        print("VERDICT: KEY ENTRIES DIFFER")
    drift = []
    for n in sorted(set(a["entries"]) | set(b["entries"])):
        ha, hb = a["entries"].get(n), b["entries"].get(n)
        tag = "KEY" if is_key(n) else "non-key"
        if ha is None:
            drift.append(f"  [{tag}] only-in-B: {n}")
        elif hb is None:
            drift.append(f"  [{tag}] only-in-A: {n}")
        elif ha != hb:
            drift.append(f"  [{tag}] differs:   {n}")
    if drift:
        print("Entry drift:")
        print("\n".join(drift))
    return 0 if a["key_digest"] == b["key_digest"] else 1

def main() -> int:
    if len(sys.argv) == 2:
        print(json.dumps(fingerprint(Path(sys.argv[1])), indent=2, sort_keys=True))
        return 0
    if len(sys.argv) == 3:
        return compare(fingerprint(Path(sys.argv[1])), fingerprint(Path(sys.argv[2])))
    print(__doc__)
    return 2

if __name__ == "__main__":
    sys.exit(main())
