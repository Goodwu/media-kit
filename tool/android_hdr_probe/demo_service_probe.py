#!/usr/bin/env python3
"""Call the opt-in Debug hdr_lab VM-service probe over an ADB local forward."""
import argparse
import json
import sys
import urllib.parse
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', nargs='?', default='snapshot',
                        choices=['snapshot', 'open', 'native-dv-open',
                                 'video-reinit', 'native-dv-facts',
                                 'native-dv-input-logs',
                                 'capabilities', 'pause', 'play', 'seek',
                                 'p5-probe'])
    parser.add_argument('--port', type=int, default=18181)
    parser.add_argument('--path')
    parser.add_argument('--seconds', type=float)
    parser.add_argument('--render-mode', choices=['boolean', 'timed'])
    parser.add_argument('--input-diag', action='store_true')
    args = parser.parse_args()
    if args.action in ('open', 'native-dv-open', 'p5-probe') and not args.path:
        parser.error('this action requires --path')
    if args.action == 'seek' and args.seconds is None:
        parser.error('seek requires --seconds')
    if args.action != 'native-dv-open' and args.render_mode is not None:
        parser.error('--render-mode is only valid with native-dv-open')
    if args.action != 'native-dv-open' and args.input_diag:
        parser.error('--input-diag is only valid with native-dv-open')
    base = f'http://127.0.0.1:{args.port}/'

    def rpc(method, **params):
        url = base + method + '?' + urllib.parse.urlencode(params)
        with urllib.request.urlopen(url, timeout=30) as response:
            return json.load(response)

    vm = rpc('getVM')
    if 'error' in vm:
        raise RuntimeError(vm['error'])
    isolate = next((i['id'] for i in vm['result']['isolates']
                    if i['name'] == 'main'), None)
    if isolate is None:
        print('No main isolate is available; is the Debug hdr_lab player running?',
              file=sys.stderr)
        return 2
    params = {'isolateId': isolate, 'action': args.action}
    if args.path is not None:
        params['path'] = args.path
    if args.action == 'native-dv-open':
        params['renderMode'] = args.render_mode or 'timed'
        params['inputDiag'] = 'true' if args.input_diag else 'false'
    if args.seconds is not None:
        params['seconds'] = args.seconds
    result = rpc('ext.media_kit.hdr_lab.probe', **params)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 1 if 'error' in result else 0


if __name__ == '__main__':
    raise SystemExit(main())
