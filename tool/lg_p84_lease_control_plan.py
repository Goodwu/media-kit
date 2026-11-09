"""Build a non-executable host-only lease A/B request plan.

A request plan is not a device result or an M2 eligibility decision.
"""


TARGET = 'debug.mks.st_lease_target'


def _check_pair(a: dict[str, str], b: dict[str, str]) -> None:
    if a.keys() != b.keys() or {key for key in a if a[key] != b[key]} != {TARGET}:
        raise ValueError('lease controls must differ only in the target request')
    if a[TARGET] != '0' or b[TARGET] != '1':
        raise ValueError('lease target must be baseline=0 and candidate=1')


def build_lease_control_plan(*, video_sync: str, pair_count: int = 3) -> dict:
    """Return requested controls only; this function cannot execute rounds."""
    if type(video_sync) is not str or video_sync not in ('display-resample', 'audio'):
        raise ValueError('video_sync must be display-resample or audio')
    if type(pair_count) is not int or not 3 <= pair_count <= 32:
        raise ValueError('pair_count must be an integer from 3 to 32')

    common = {
        'debug.mks.thermal_sync': video_sync,
        'debug.mks.thermal_trace': '1',
        'debug.mks.defer_publish_flush': '0',
        'debug.mks.gpu_timing': '0',
        'debug.mks.yuv_fusion': '1',
        'debug.mks.yuv_fusion_table': '0',
        'debug.mks.yuv_fail_commit': '0',
        'debug.mks.yuv_fail_gl': '0',
        'debug.mks.st_fbo': '0',
        'debug.mks.st_lease_rgba16': '0',
    }
    pairs = []
    for number in range(1, pair_count + 1):
        a, b = {**common, TARGET: '0'}, {**common, TARGET: '1'}
        _check_pair(a, b)
        rounds = {
            'A': {'roundId': f'pair-{number:02d}-A', 'mode': 'baseline', 'requestedProperties': a},
            'B': {'roundId': f'pair-{number:02d}-B', 'mode': 'candidate', 'requestedProperties': b},
        }
        order = ('A', 'B') if number % 2 else ('B', 'A')
        pairs.append({'pairId': f'pair-{number:02d}', 'plannedRounds': [rounds[key] for key in order]})

    return {
        'schema': 'lg-p84-lease-control-plan/v1',
        'artifactKind': 'requested-control-plan',
        'executionAllowed': False,
        'm2Eligible': False,
        'm2Verdict': 'not-evaluated',
        'planChecks': {'controlDeltaOnly': True},
        'videoSync': video_sync,
        'pairCount': pair_count,
        'pairs': pairs,
        'evidence': {
            'requested': 'planned-only',
            'readback': 'not-collected',
            'published': 'not-collected',
            'consumed': 'not-collected',
            'timing': 'unsupported-for-M2',
            'samePackage': 'unverified',
        },
        'unbound': ['apk-and-loaded-native-source', 'source-identity', 'thermal-anchor',
                    'duration-and-stable-window', 'device-state-and-actual-order'],
    }
