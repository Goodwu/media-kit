#!/usr/bin/env python3
"""Compare GLES and Vulkan Y values recorded in one ImageReader callback."""

import json
import re
import sys
from pathlib import Path


def sample_from_run(path: Path, ordinal: int):
    text = path.read_text()
    start = text.index("surfaceImages=[") + len("surfaceImages=[")
    end = text.index("}],", start) + 1
    entries = text[start:end].split("}, {")
    matches = [entry for entry in entries if f"matchedOutputOrdinal={ordinal}" in entry]
    if len(matches) != 1:
        raise ValueError(f"{path}: expected one frame {ordinal}, got {len(matches)}")
    entry = matches[0]
    if ("hardwareBufferFormat=805" not in entry or "requestedRange=0" not in entry
            or "gpuImport=" not in entry or "vulkanImport=" not in entry):
        raise ValueError(f"{path}: wrong buffer format or range")
    if "timestampNs=10000000000" not in entry or "timestampMatchesOutputPts=true" not in entry:
        raise ValueError(f"{path}: timestamp does not match frame ordinal")
    gl = re.findall(r"pt-(\d+),(\d+)=(\d+),(\d+),(\d+) err=0x([0-9a-f]+)", entry)
    vk = re.findall(r"(\d+):\(([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+)\)", entry)
    if "rawYuvFull=" not in entry or len(gl) < 10 or len(vk) != 10:
        raise ValueError(f"{path}: missing raw points")
    gl = gl[-10:]
    if any(item[-1] != "0" for item in gl):
        raise ValueError(f"{path}: missing points or GLES read error")
    rows = []
    for index, (g, v) in enumerate(zip(gl, vk)):
        if int(v[0]) != index:
            raise ValueError(f"{path}: Vulkan point order")
        rows.append({"xy": [int(g[0]), int(g[1])], "gl_y": int(g[2]),
                     "vulkan_y": float(v[2]), "vulkan_y_10bit": round(float(v[2]) * 1023)})
    return {"file": str(path), "ordinal": ordinal, "rows": rows,
            "all_y_equal": all(row["gl_y"] == row["vulkan_y_10bit"] for row in rows)}


def main():
    if len(sys.argv) != 4:
        raise SystemExit("usage: script original-run.txt pattern-run.txt output.json")
    results = [sample_from_run(Path(sys.argv[1]), 500),
               sample_from_run(Path(sys.argv[2]), 240)]
    Path(sys.argv[3]).write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n")
    if not all(result["all_y_equal"] for result in results):
        raise SystemExit("GLES/Vulkan Y mismatch")
    print("same-AHB GLES/Vulkan Y: 20/20 match")


if __name__ == "__main__":
    main()
