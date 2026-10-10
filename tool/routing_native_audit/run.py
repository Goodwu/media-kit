#!/usr/bin/env python3
"""Compile current FFmpeg selection regions with JNI fixtures, not a player.

No source revision or prebuilt library is selected by this tool. A checkout
must be updated by the caller. Captured regions are accepted only when that
limited scope is explicitly reported; they are not a full FFmpeg build.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def block_end(text: str, start: int) -> int:
    """Return the offset after a balanced C block, ignoring comments/literals."""
    if start >= len(text) or text[start] != '{':
        raise ValueError('Expected a C block')
    depth, i, state = 0, start, 'code'
    while i < len(text):
        c, pair = text[i], text[i:i + 2]
        if state == 'line':
            if c == '\n':
                state = 'code'
        elif state == 'comment':
            if pair == '*/':
                state = 'code'
                i += 1
        elif state in ('"', "'"):
            if c == '\\':
                i += 1
            elif c == state:
                state = 'code'
        elif pair == '//':
            state = 'line'
            i += 1
        elif pair == '/*':
            state = 'comment'
            i += 1
        elif c in ('"', "'"):
            state = c
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError('Unterminated C block; refusing partial extraction')


def unique_match(pattern: str, text: str) -> re.Match[str]:
    matches = list(re.finditer(pattern, text))
    if len(matches) != 1:
        raise ValueError(f'Expected one source anchor, found {len(matches)}')
    return matches[0]


def extract_selection(text: str) -> str:
    marker = unique_match(
        r'\bchar\s*\*\s*ff_AMediaCodecList_getCodecNameByType\s*\(', text)
    opening = text.index('{', marker.end())
    return text[marker.start():block_end(text, opening)] + '\n'


def extract_lookup(text: str) -> str:
    marker = unique_match(
        r'\bif\s*\(\s*format_profile\s*==\s*0x20\s*\)\s*\{', text)
    first_end = block_end(text, marker.end() - 1)
    following = re.match(r'\s*else\s*\{', text[first_end:])
    if following is None:
        raise ValueError('Native DV profile branch changed; review the harness')
    last = block_end(text, first_end + following.end() - 1)
    return text[marker.start():last] + '\n'


def run_command(command: list[str], output: Path, timeout: int) -> int:
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=timeout,
                            check=False)
    output.write_text(result.stdout, encoding='utf-8')
    print(result.stdout, end='')
    return result.returncode


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ffmpeg-root', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--cc', default=os.environ.get('CC', 'cc'))
    parser.add_argument('--sanitize', action='store_true')
    parser.add_argument('--input-scope', choices=['checkout', 'captured-regions'],
                        default='checkout')
    args = parser.parse_args()
    root, output = args.ffmpeg_root.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    harness = Path(__file__).with_name('native_selection_harness.c').resolve()
    paths = {
        'wrapper': root / 'libavcodec/mediacodec_wrapper.c',
        'common': root / 'libavcodec/mediacodecdec_common.c',
        'harness': harness,
    }
    receipt: dict[str, object] = {
        'taskId': 'MK-ROUTING-20261011',
        'scope': 'host-C-selection-with-JNI-fixtures',
        'inputScope': args.input_scope,
        'fullNativeBuild': False,
        'deviceTest': False,
        'status': 'preparing',
    }
    try:
        before = {name: path.read_bytes() for name, path in paths.items()}
        receipt['inputSha256'] = {name: sha(data) for name, data in before.items()}
        regions = {
            'selection.c.inc': extract_selection(before['wrapper'].decode('utf-8')),
            'lookup.c.inc': extract_lookup(before['common'].decode('utf-8')),
        }
        for name, content in regions.items():
            (output / name).write_text(content, encoding='utf-8')
        receipt['regionSha256'] = {
            name: sha(content.encode('utf-8')) for name, content in regions.items()
        }
        compiler = shlex.split(args.cc)
        if not compiler:
            raise ValueError('Compiler command is empty')
        command = compiler + ['-std=c11', '-Wall', '-Wextra', '-Werror', '-O0', '-g']
        if args.sanitize:
            command += ['-fsanitize=address,undefined', '-fno-omit-frame-pointer']
        executable = output / 'native-selection-test'
        command += ['-I', str(output), str(harness), '-o', str(executable)]
        receipt['compileCommand'] = command
        compile_exit = run_command(command, output / 'compile.log', 30)
        receipt['compileExit'] = compile_exit
        if compile_exit:
            receipt['status'] = 'compile-failed'
            return 2
        run_exit = run_command([str(executable)], output / 'regression.log', 10)
        receipt['regressionExit'] = run_exit
        unchanged = all(path.read_bytes() == before[name] for name, path in paths.items())
        receipt['inputsUnchanged'] = unchanged
        if not unchanged:
            receipt['status'] = 'source-changed-during-run'
            return 2
        receipt['status'] = 'passed' if run_exit == 0 else 'failing-regression'
        return 0 if run_exit == 0 else 1
    except (OSError, ValueError, UnicodeError, subprocess.TimeoutExpired) as error:
        receipt['status'] = 'harness-error'
        receipt['error'] = str(error)
        print(str(error), file=sys.stderr)
        return 2
    finally:
        (output / 'receipt.json').write_text(
            json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    raise SystemExit(main())
