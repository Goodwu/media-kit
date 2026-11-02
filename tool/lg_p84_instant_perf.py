#!/usr/bin/env python3
"""Short LG HDR playback CPU/GPU profile using the reviewed thermal lifecycle.

One sampler owns GPU counter reads. No frequency, voltage, root or driver
settings are changed. Driver-reported rails/corners/battery stay distinct.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
import shlex
import signal
import statistics
import struct
import subprocess
import time
from typing import Any

import lg_p84_thermal_round as thermal


NODES = {
    'uptime': '/proc/uptime', 'cpu_total': '/proc/stat',
    'cpu_online': '/sys/devices/system/cpu/online',
    'battery_type': '/sys/class/thermal/thermal_zone30/type',
    'battery_temp': '/sys/class/thermal/thermal_zone30/temp',
    'vts_type': '/sys/class/thermal/thermal_zone39/type',
    'vts_temp': '/sys/class/thermal/thermal_zone39/temp',
    'backlight': '/sys/class/leds/lcd-backlight/brightness',
    'backlight_max': '/sys/class/leds/lcd-backlight/max_brightness',
    'hdr_mode': '/sys/devices/virtual/panel/img_tune/hdr_mode',
    'panel_thermal_status': '/sys/class/leds/lcd-backlight/thermald_status',
    'gpu_hz': '/sys/class/kgsl/kgsl-3d0/gpuclk',
    'gpu_thermal_pwrlevel': '/sys/class/kgsl/kgsl-3d0/thermal_pwrlevel',
    'gpu_max_gpuclk': '/sys/class/kgsl/kgsl-3d0/max_gpuclk',
    'cpu2_scaling_max_freq': '/sys/devices/system/cpu/cpu2/cpufreq/scaling_max_freq',
    'gpu_driver_busy_percentage': '/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage',
    'battery_status': '/sys/class/power_supply/battery/status',
    'battery_voltage_now': '/sys/class/power_supply/battery/voltage_now',
    'battery_current_now': '/sys/class/power_supply/battery/current_now',
    'battery_capacity': '/sys/class/power_supply/battery/capacity',
    'usb_online': '/sys/class/power_supply/usb/online',
    'ac_online': '/sys/class/power_supply/ac/online',
    'cpu_kryo0_regulator_name': '/sys/class/regulator/regulator.7/name',
    'cpu_kryo0_regulator_microvolts': '/sys/class/regulator/regulator.7/microvolts',
    'cpu_kryo1_regulator_name': '/sys/class/regulator/regulator.9/name',
    'cpu_kryo1_regulator_microvolts': '/sys/class/regulator/regulator.9/microvolts',
    'gpu_upstream_regulator_name': '/sys/class/regulator/regulator.1/name',
    'gpu_upstream_regulator_microvolts': '/sys/class/regulator/regulator.1/microvolts',
    'gpu_corner_name': '/sys/class/regulator/regulator.63/name',
    'gpu_corner_raw': '/sys/class/regulator/regulator.63/microvolts',
}
for cpu in range(4):
    NODES[f'cpu{cpu}_khz'] = f'/sys/devices/system/cpu/cpu{cpu}/cpufreq/scaling_cur_freq'


def cpu_stat(text: str) -> dict[str, tuple[int, int]]:
    result = {}
    for line in text.splitlines():
        fields = line.split()
        if fields and re.fullmatch(r'cpu\d*', fields[0]):
            values = [int(v) for v in fields[1:9]]
            if len(values) >= 5:
                result[fields[0]] = (sum(values), values[3] + values[4])
    return result


def task_stat(text: str) -> dict[str, Any] | None:
    try:
        pid = text.split(' ', 1)[0]
        name = text.split('(', 1)[1].rsplit(')', 1)[0]
        fields = text.rsplit(')', 1)[1].split()
        return {'tid': pid, 'name': name, 'ticks': int(fields[11]) + int(fields[12]), 'startTicks': int(fields[19])}
    except (ValueError, IndexError):
        return None


def delta(previous: dict[str, Any], current: dict[str, Any], clock_hz: int) -> dict[str, Any]:
    dt = current['deviceUptime'] - previous['deviceUptime']
    result: dict[str, Any] = {'intervalSeconds': dt, 'systemBusyPercent': {}, 'processOneCorePercent': None, 'threadOneCorePercent': []}
    if dt <= 0:
        return result
    before, after = cpu_stat(previous['raw'].get('cpu_total', '')), cpu_stat(current['raw'].get('cpu_total', ''))
    for key, (total, idle) in after.items():
        if key not in before:
            continue
        td, idle_delta = total-before[key][0], idle-before[key][1]
        if td > 0 and 0 <= idle_delta <= td:
            result['systemBusyPercent'][key] = 100 * (td-idle_delta)/td
    if current['pid'] == previous['pid'] and current.get('processStartTicks') == previous.get('processStartTicks'):
        tick_delta = current['appCpuTicks'] - previous['appCpuTicks'] if None not in (current['appCpuTicks'], previous['appCpuTicks']) else -1
        if tick_delta >= 0:
            result['processOneCorePercent'] = 100*tick_delta/(clock_hz*dt)
        old = {r['tid']: r for r in previous['tasks']}
        for row in current['tasks']:
            prior = old.get(row['tid'])
            if prior and row['startTicks'] == prior['startTicks'] and row['ticks'] >= prior['ticks']:
                result['threadOneCorePercent'].append({'tid': row['tid'], 'name': row['name'], 'percent': 100*(row['ticks']-prior['ticks'])/(clock_hz*dt)})
        result['threadOneCorePercent'].sort(key=lambda r:r['percent'], reverse=True)
    return result


class InstantAdb(thermal.Adb):
    clock_hz = 100

    def __init__(self, serial: str, output: Path):
        super().__init__(serial, output)
        self.previous = None
        self.screen_cached = None
        self.screen_at = 0.0
        self.ordinal = 0

    def snapshot(self) -> dict[str, Any]:
        started = time.monotonic()
        pid = self.lab_pid()
        nodes = dict(NODES)
        if pid and pid.isdigit():
            nodes['app_stat'] = f'/proc/{pid}/stat'
        # gpubusy is a validation probe only (zero denominator => unknown),
        # not a second concurrent utilisation reader or a reported 0% value.
        if self.ordinal == 0:
            nodes['gpu_busy_validation_raw'] = '/sys/class/kgsl/kgsl-3d0/gpubusy'
        if self.ordinal % 10 == 0:
            nodes['gpu_residency'] = '/sys/class/kgsl/kgsl-3d0/devfreq/trans_stat'
            nodes['cpu0_residency'] = '/sys/devices/system/cpu/cpu0/cpufreq/stats/time_in_state'
            nodes['cpu2_residency'] = '/sys/devices/system/cpu/cpu2/cpufreq/stats/time_in_state'
        script = '\n'.join(f'echo "@@ {key}"; cat {shlex.quote(path)} 2>/dev/null || true' for key,path in nodes.items())
        if pid and pid.isdigit():
            script += f'\necho "@@ threads"; for f in /proc/{pid}/task/*/stat; do cat "$f" 2>/dev/null; done\n'
        raw = thermal.parse_blocks(self.shell(script))
        at = time.monotonic()
        if self.screen_cached is None or at-self.screen_at >= 10:
            self.screen_cached = self.screen_state()
            self.screen_at = time.monotonic()
        battery_c, vts_c = thermal.temperature(raw)
        task = task_stat(raw.get('app_stat',''))
        tasks = [r for line in raw.get('threads','').splitlines() if (r:=task_stat(line))]
        busy_match = re.fullmatch(r'\s*(\d+(?:\.\d+)?)\s*%\s*',raw.get('gpu_driver_busy_percentage',''))
        busy = float(busy_match.group(1)) if busy_match else None
        if busy is not None and not 0 <= busy <= 100:
            busy = None
        sample = {'hostTime': thermal.now(), 'hostMonotonic': at, 'pid': pid,
                  'batteryC': battery_c, 'vtsC': vts_c,
                  'deviceUptime': float(raw['uptime'].split()[0]),
                  'appCpuTicks': None if task is None else task['ticks'],
                  'processStartTicks': None if task is None else task['startTicks'],
                  'tasks': tasks, 'screen': dict(self.screen_cached), 'raw': raw,
                  'gpuDriverReportedBusyPercent': busy,
                  'samplingWorkSeconds': time.monotonic()-started,
                  'clockTicksPerSecond': self.clock_hz}
        if self.previous:
            sample['cpuDelta'] = delta(self.previous, sample, self.clock_hz)
        self.previous = sample
        self.ordinal += 1
        return sample


def measure_clock(serial: str) -> int:
    r = subprocess.run(['adb','-s',serial,'exec-out','cat','/proc/self/auxv'],capture_output=True,timeout=10)
    if r.returncode:
        raise RuntimeError('Cannot obtain device AT_CLKTCK; refusing guessed CPU percent')
    matches=[]
    for width,fmt in [(8,'<QQ'),(4,'<II')]:
        if len(r.stdout)%(width*2):
            continue
        entries=dict(struct.unpack(fmt,r.stdout[i:i+width*2]) for i in range(0,len(r.stdout),width*2))
        if entries.get(6) in (4096,16384,65536) and 1 <= entries.get(17,0) <= 10000:
            matches.append(entries[17])
    if len(matches)!=1:
        raise RuntimeError('Ambiguous or missing device AT_CLKTCK')
    return matches[0]


def summarize(output: Path, controller: dict[str, Any], source: str) -> dict[str, Any]:
    rows=[json.loads(line) for line in (output/'samples.ndjson').read_text().splitlines()] if (output/'samples.ndjson').exists() else []
    stable=[]
    for row in rows:
        state=row.get('runtime',{})
        valid=(row.get('elapsedSeconds',0)>=10 and
               thermal.runtime_error(state, controller['requestedVideoSync'], row.get('pid'), source) is None and
               row['raw'].get('hdr_mode')=='1' and row['raw'].get('backlight')==controller.get('expectedBacklight', '255') and
               row['raw'].get('panel_thermal_status')==controller.get('expectedPanelThermalStatus') and
               thermal.native_failure_reason(state) is None and
               thermal.gpu_thermal_cap_reason(row) is None)
        if valid and controller.get('experiment')=='fusion-table':
            valid=thermal.fusion_table_state(state)==controller.get('requestedFusionTable','off') if False else valid
        if valid and controller.get('experiment')=='publish-flush':
            valid=thermal.publish_policy_error(state, controller['requestedDeferPublishFlush']) is None
        if valid and controller.get('inputFboValidationRequired'):
            since = state.get('playbackStartAt')
            valid = since is not None and thermal.input_fbo_error(state, controller['requestedInputFbo'], since=since+10) is None
        if valid:stable.append(row)
    cpu=[r['cpuDelta']['processOneCorePercent'] for r in stable if r.get('cpuDelta',{}).get('processOneCorePercent') is not None]
    gpu=[r['gpuDriverReportedBusyPercent'] for r in stable if r.get('gpuDriverReportedBusyPercent') is not None]
    def stats(values):
        return {'count':len(values),'min':min(values),'median':statistics.median(values),'max':max(values)} if values else None
    gpu_gate_verified=bool(rows) and all(thermal.gpu_thermal_cap_reason(r) is None for r in rows) and thermal.gpu_thermal_cap_reason(controller.get('initial',{})) is None
    fbo_gate_verified = not controller.get('inputFboValidationRequired') or controller.get('inputFboVerified') is True
    result={'gpuThermalGateVerified':gpu_gate_verified,
            'inputFboGateVerified': fbo_gate_verified,
            'gpuThermalGateNormalPwrlevel':0,
            'gpuThermalGateScope':'Observed LG experimental normal baseline; unknown/nonzero fail closed; caps are metadata, not measured clock or CPU thermal causality.',
            'controllerStatus':controller.get('status'), 'controllerReason':controller.get('reason'),
            'validCompletedProfile':controller.get('status')=='completed-observation' and controller.get('completeWindow') is True and controller.get('restorationVerified') is True and bool(stable) and gpu_gate_verified and fbo_gate_verified,
            'metricsAreDiagnosticOnly':controller.get('status')!='completed-observation' or controller.get('restorationVerified') is not True or not gpu_gate_verified or controller.get('completeWindow') is not True or not fbo_gate_verified,
            'stableSamples':len(stable),'processCPUPercentOneCore100':stats(cpu),
            'gpuDriverReportedBusyPercent':stats(gpu),
            'gpuFrequencyHz':stats([v for r in stable if (v:=thermal.number(r['raw'].get('gpu_hz'))) is not None]),
            'cpuFrequencyKHz':{f'cpu{i}':stats([v for r in stable if (v:=thermal.number(r['raw'].get(f'cpu{i}_khz'))) is not None]) for i in range(4)},
            'reportedVoltageMicrovolts':{k:stats([v for r in stable if (v:=thermal.number(r['raw'].get(k))) is not None]) for k in ['cpu_kryo0_regulator_microvolts','cpu_kryo1_regulator_microvolts','gpu_upstream_regulator_microvolts','battery_voltage_now']},
            'limitations':['CPU process/thread 100% means one fully busy CPU core, not all four cores.',
                           'GPU utilisation is the named driver percentage report, not inferred from frequency; raw gpubusy zero denominator is unknown.',
                           'Regulator microvolts are software reports/targets, not optical or electrical probe measurements; GPU upstream supply is not a measured core voltage.',
                           'gpu_corner_raw is a corner index even though sysfs file is named microvolts; it is never converted to volts.',
                           'Battery voltage/current are separate power-supply fields; they do not measure CPU/GPU rail power.',
                           'Sampling overhead is recorded per row and is included in system busy counters.']}
    thread_sums={}
    for r in stable:
        for t in r.get('cpuDelta',{}).get('threadOneCorePercent',[]):
            key=(t['tid'],t['name']);thread_sums.setdefault(key,[]).append(t['percent'])
    result['topThreads']=[{'tid':key[0],'name':key[1],'meanOneCorePercent':statistics.mean(values),'maxOneCorePercent':max(values),'samples':len(values)} for key,values in sorted(thread_sums.items(),key=lambda item:statistics.mean(item[1]),reverse=True)[:15]]
    thermal.write_json(output/'instant-summary.json',result)
    return result


def main() -> int:
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--serial',required=True);p.add_argument('--output',required=True)
    p.add_argument('--mode',choices=thermal.MODES,required=True)
    p.add_argument('--experiment',choices=('sync','publish-flush','input-fbo','fusion-table'),default='sync')
    p.add_argument('--st-fbo', choices=('0','1'), help='Explicit 0/1 path. input-fbo maps baseline=0/candidate=1; effective fresh mapper work is required.')
    p.add_argument('--duration',type=float,default=60);p.add_argument('--interval',type=float,default=2)
    p.add_argument('--tap',type=int,nargs=2,default=[1440,720]);p.add_argument('--tap-delay',type=float,default=4)
    p.add_argument('--allow-unprotected-menu',action='store_true')
    p.add_argument('--expected-panel-thermal-status',required=True,help='Value independently approved by Lead as this round normal precondition; unknown or different values stop')
    p.add_argument('--source',default='/sdcard/Android/data/com.example.media_kit_hdr_lab/files/hokkaido-p84.mp4')
    g=p.add_mutually_exclusive_group(required=True);g.add_argument('--source-receipt');g.add_argument('--source-hash')
    p.add_argument('--gpu-timing',choices=('input','yuv','render'))
    p.add_argument('--yuv-fusion',action='store_true')
    p.add_argument('--yuv-fault',choices=('commit','gl'))
    p.add_argument('--brightness',type=int,default=255)
    p.add_argument('--expected-backlight',type=int,default=255)
    args=p.parse_args()
    if args.experiment == 'fusion-table':
        args.yuv_fusion = True
        args.fusion_table = True
    if args.yuv_fault and not args.yuv_fusion:
        p.error('fault injection requires --yuv-fusion')
    if not 1 <= args.brightness <= 255 or not 1 <= args.expected_backlight <= 255:
        p.error('brightness and expected backlight must be 1..255')
    if not 30<=args.duration<=360 or not 1<=args.interval<=2:
        p.error('profile duration30..360s, interval1..2s only')
    args.instant_enabled=True
    args.reference_start=None;args.cooldown_timeout=0;args.battery_tolerance=0.5;args.vts_tolerance=1
    InstantAdb.clock_hz=measure_clock(args.serial)
    thermal.Adb=InstantAdb
    def terminate(signum,frame):raise KeyboardInterrupt('termination-signal-'+str(signum))
    signal.signal(signal.SIGTERM,terminate)
    result=thermal.run(args)
    summary=summarize(Path(args.output).resolve(),result,args.source)
    print(json.dumps({'status':result['status'],'reason':result.get('reason'),'restorationVerified':result.get('restorationVerified'),'instant':summary},ensure_ascii=False),flush=True)
    return 0 if result['status']=='completed-observation' and result['restorationVerified'] else 2


if __name__=='__main__':raise SystemExit(main())
