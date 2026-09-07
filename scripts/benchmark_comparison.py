#!/usr/bin/env python3
"""Validated cross-language temporal benchmarks. See benchmarks/comparison/README.md."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import sys
import urllib.request

sys.dont_write_bytecode = True
import benchmark_chrono as common

ROOT = common.ROOT
BASE = ROOT / 'benchmarks/comparison'
BUILD = ROOT / '.roc-time-tmp/announcement'
PINS = json.loads((BASE / 'dependencies.json').read_text())
TEMPO = BUILD / 'tempo'
SMALL = ('date_control', 'construct', 'add_days', 'parse', 'resolve')
MODES = common.MODES


def call(args, **kw):
    try:
        return subprocess.run([str(a) for a in args], cwd=ROOT, check=True, timeout=300, **kw)
    except subprocess.CalledProcessError as error:
        if error.stderr:
            print(error.stderr, file=sys.stderr)
        raise


def capture(args, **kw):
    return call(args, capture_output=True, text=True, **kw).stdout.strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def docker_prefix(cpu=None):
    return ['docker', 'run', '--rm', '--network=none',
            *([] if cpu is None else [f'--cpuset-cpus={cpu}']),
            '-e', 'MIX_ENV=prod', '-e', 'HEX_HOME=/work/.hex', '-e', 'MIX_HOME=/work/.mix',
            '-e', 'ERL_FLAGS=+S 1:1', '-v', f'{TEMPO}:/work', '-w', '/work', PINS['tempo']['image']]


def controls():
    for bad in ('10,2\n', '10,1\nextra\n', 'bad\n', '10,1\n\n', '\n10,1\n', '0,1\n', '-1,1\n', ''):
        try:
            common.parse_samples(bad, 1, 1)
        except (ValueError, TypeError):
            continue
        raise AssertionError(f'accepted malformed result: {bad!r}')
    if common.parse_samples('10,1\n', 1, 1) != [10]:
        raise AssertionError('positive control failed')


def prepare(fetch):
    BUILD.mkdir(parents=True, exist_ok=True)
    versions = {'python': platform.python_version(), 'go': capture(['go', 'version']),
                'rust': capture([os.environ.get('RUSTC', 'rustc'), '-Vv']), 'roc': capture([os.environ.get('ROC', 'roc'), 'version'])}
    if versions['python'] != PINS['python'] or versions['go'].split()[2] != PINS['go']:
        raise RuntimeError(f'Toolchain differs from dependencies.json: {versions}')
    env = {**os.environ, 'CARGO_HOME': str(ROOT / '.roc-time-tmp/chrono-cargo'),
           'CARGO_TARGET_DIR': str(BUILD / 'jiff-target')}
    if fetch:
        pin = PINS['ciso8601']
        source = BUILD / pin['wheel_filename']
        with urllib.request.urlopen(pin['wheel_url'], timeout=60) as response:
            source.write_bytes(response.read())
        if digest(source) != pin['wheel_sha256']:
            raise RuntimeError('ciso8601 source integrity mismatch')
        call([sys.executable, '-m', 'pip', 'install', '--no-deps', '--upgrade',
              '--target', BUILD / 'python', source], env={**os.environ, 'TMPDIR': str(BUILD)})
        if not TEMPO.exists():
            call(['git', 'init', TEMPO])
            call(['git', '-C', TEMPO, 'remote', 'add', 'origin', 'https://github.com/elixir-tempo/tempo.git'])
            call(['git', '-C', TEMPO, 'fetch', '--depth=1', 'origin', PINS['tempo']['revision']])
            call(['git', '-C', TEMPO, 'checkout', '--detach', 'FETCH_HEAD'])
        call(['docker', 'pull', PINS['tempo']['image']])
        # Dependency acquisition is the only container operation with networking.
        cmd = docker_prefix()
        cmd.remove('--network=none')
        call([*cmd, 'sh', '-c', 'mix local.hex --force && mix local.rebar --force && mix deps.get && mix compile'])
        call(['cargo', 'fetch', '--locked', '--manifest-path', BASE / 'rust/Cargo.toml'], env=env)
    if capture(['git', '-C', TEMPO, 'rev-parse', 'HEAD']) != PINS['tempo']['revision']:
        raise RuntimeError('Tempo source revision mismatch')
    if digest(TEMPO / 'mix.lock') != PINS['tempo']['mix_lock_sha256']:
        raise RuntimeError('Tempo dependency lock mismatch')
    if capture(['git', '-C', TEMPO, 'diff', 'HEAD', '--', 'lib', 'mix.exs', 'mix.lock']):
        raise RuntimeError('Tempo source modified')
    pyenv = {**os.environ, 'PYTHONPATH': str(BUILD / 'python')}
    versions['ciso8601'] = capture([sys.executable, '-c', 'import ciso8601; print(ciso8601.__version__)'], env=pyenv)
    if versions['ciso8601'] != PINS['ciso8601']['version']:
        raise RuntimeError('ciso8601 version mismatch')
    # Reuse the reviewed Roc/Chrono build, pin validation and per-case oracle gate.
    call([sys.executable, ROOT / 'scripts/benchmark_chrono.py', '--smoke', *(['--fetch'] if fetch else [])])
    call(['cargo', 'build', '--offline', '--locked', '--release', '--target', 'x86_64-unknown-linux-musl',
          '--manifest-path', BASE / 'rust/Cargo.toml'], env=env)
    call(['go', 'build', '-trimpath', '-o', BUILD / 'go-bench', BASE / 'go_bench.go'],
         env={**os.environ, 'CGO_ENABLED': '0', 'GOCACHE': str(BUILD / 'go-cache')})
    shutil.copyfile(BASE / 'tempo_bench.exs', TEMPO / 'comparison_bench.exs')
    versions['elixir'] = capture([*docker_prefix(), 'elixir', '--version'])
    return versions, pyenv


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--fetch', action='store_true')
    p.add_argument('--smoke', action='store_true')
    p.add_argument('--iterations', type=int, default=100000)
    p.add_argument('--warmups', type=int, default=3)
    p.add_argument('--samples', type=int, default=9)
    p.add_argument('--rounds', type=int, default=3)
    p.add_argument('--profile', choices=('microseconds', 'seconds', 'both'), default='both')
    p.add_argument('--cpu', type=int, help='pin all measured processes to this available Linux CPU')
    o = p.parse_args()
    if platform.system() != 'Linux' or platform.machine() != 'x86_64':
        p.error('this comparison currently supports Linux x86-64 only')
    if o.smoke:
        o.iterations, o.warmups, o.samples, o.rounds = 1000, 1, 3, 1
    if not (1 <= o.iterations <= 10000000 and 0 <= o.warmups <= 10 and 1 <= o.samples <= 50 and 1 <= o.rounds <= 10):
        p.error('bounds: iterations 1..10000000, warmups 0..10, samples 1..50, rounds 1..10')
    controls()
    versions, pyenv = prepare(o.fetch)
    if o.cpu is not None:
        if o.cpu not in os.sched_getaffinity(0):
            p.error('CPU is outside available affinity')
        os.sched_setaffinity(0, {o.cpu})
    chrono = ROOT / '.roc-time-tmp/chrono-benchmark'
    # (command prefix, supported workloads, optional native executable).
    adapters = {
        'roc-time': (['benchmark'], MODES, chrono / 'roc-speed'),
        'chrono': (['benchmark'], MODES, chrono / 'cargo-target/x86_64-unknown-linux-musl/release/roc-time-chrono-benchmark'),
        'jiff': (['benchmark'], SMALL, BUILD / 'jiff-target/x86_64-unknown-linux-musl/release/roc-time-jiff-benchmark'),
        'go-time': (['benchmark'], MODES, BUILD / 'go-bench'),
        'datetime': ([sys.executable, BASE / 'python_bench.py', 'datetime'], MODES, None),
        'ciso8601': ([sys.executable, BASE / 'python_bench.py', 'ciso8601'], ('parse', 'parse_only', 'end_to_end'), None),
        'tempo': ([*docker_prefix(o.cpu), 'mix', 'run', '--no-start', '--no-compile', '--no-deps-check', 'comparison_bench.exs'], (*SMALL, 'date_to_day'), None),
    }
    profiles = {'microseconds': common.BASE / 'corpus.jsonl', 'seconds': BASE / 'seconds.jsonl'}
    if o.profile != 'both':
        profiles = {o.profile: profiles[o.profile]}
    results = []
    limitations = []
    for profile, corpus_path in profiles.items():
        corpus = [json.loads(line) for line in corpus_path.read_text().splitlines()]
        if not corpus or any(case != common.oracle(case['text']) for case in corpus):
            raise ValueError('independent corpus validation failed')
        texts = [v['text'] for v in corpus]
        def execute(name, mode, n, w, s):
            cmd, _, binary = adapters[name]
            return call([*cmd, mode, str(n), str(w), str(s), *texts], capture_output=True, text=True,
                        env=pyenv, **({} if binary is None else {'executable': str(binary)})).stdout
        active = dict(adapters)
        if profile == 'microseconds':
            # Preserve an observed upstream limitation, not a silently filtered corpus.
            cmd, _, _ = adapters['tempo']
            probe = subprocess.run(
                [str(a) for a in [*cmd, 'verify', '1', '0', '0', '1900-02-28T01:13:17.027183-03:30']],
                cwd=ROOT, capture_output=True, text=True, timeout=30)
            if probe.returncode == 0 or 'Tempo.ParseError' not in probe.stderr or '.027183-03:30' not in probe.stderr:
                raise RuntimeError('Tempo fractional-offset behavior changed; review the compatibility profile')
            limitations.append({'library': 'tempo', 'profile': profile, 'reason': probe.stderr})
            del active['tempo']
        for name in active:
            expected = '\n'.join(f'{v["day"]}|{v["microseconds"]}' + ('' if name == 'tempo' else
                f'|{v["text"] if name == "roc-time" and profile == "seconds" else v["canonical"]}') for v in corpus)
            if execute(name, 'verify', 1, 0, 0) != expected + '\n':
                raise ValueError(f'{name}: per-case outputs disagree with oracle ({profile})')
        print(f'PASS {profile}: independent per-case oracle and harness negative controls', flush=True)
        # Whole-second formatting would have different output precision in Roc;
        # only equivalent numerical observations are compared for that profile.
        modes = MODES if profile == 'microseconds' else tuple(m for m in MODES if m not in ('format', 'end_to_end'))
        for rnd in range(o.rounds):
            for index, mode in enumerate(modes):
                names = [name for name, (_, supported, _) in active.items() if mode in supported]
                shift = (rnd + index) % len(names)
                names = names[shift:] + names[:shift]
                if rnd % 2:
                    names.reverse()
                for name in names:
                    elapsed = common.parse_samples(execute(name, mode, o.iterations, o.warmups, o.samples),
                                                   o.samples, common.expected_sum(corpus, mode, o.iterations))
                    value = statistics.median(elapsed) / o.iterations
                    results.append({'profile': profile, 'round': rnd + 1, 'library': name, 'workload': mode,
                                    'nanoseconds': elapsed, 'median_ns_per_operation': value})
                    print(f'{profile} round {rnd+1} {name:10} {mode:12} {value:12.2f} ns/op', flush=True)
    sources = [path for path in BASE.rglob('*') if path.is_file() and 'target' not in path.parts]
    sources += [ROOT / 'scripts/benchmark_comparison.py', ROOT / 'scripts/benchmark_chrono.py']
    sources += [path for path in common.BASE.rglob('*') if path.is_file() and 'target' not in path.parts]
    report = {'scope': 'bounded Gregorian/fixed-offset throughput; no library-wide ranking or memory claims',
              'options': vars(o), 'versions': versions, 'dependencies': PINS,
              'targets': {'roc': 'x64musl/speed', 'rust': 'x86_64-unknown-linux-musl/release', 'go': 'linux/amd64 CGO_ENABLED=0'},
              'binary_sha256': {name: digest(binary) for name, (_, _, binary) in adapters.items() if binary is not None},
              'python_extension_sha256': digest(Path(capture([sys.executable, '-c', 'import ciso8601; print(ciso8601.__file__)'], env=pyenv))),
              'zig': capture([os.environ.get('ZIG', 'zig'), 'version']),
              'platform': platform.platform(), 'cpuinfo': Path('/proc/cpuinfo').read_text().split('\n\n')[0],
              'affinity': sorted(os.sched_getaffinity(0)), 'loadavg_after': os.getloadavg(),
              'cpu_governors': {str(cpu): path.read_text().strip() for cpu in os.sched_getaffinity(0)
                  if (path := Path(f'/sys/devices/system/cpu/cpu{cpu}/cpufreq/scaling_governor')).exists()},
              'git_revision': capture(['git', 'rev-parse', 'HEAD']), 'working_tree': capture(['git', 'status', '--short']),
              'source_sha256': {str(path.relative_to(ROOT)): digest(path) for path in sources},
              'corpus_sha256': {name: digest(path) for name, path in profiles.items()},
              'limitations': limitations, 'results': results}
    stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
    destination = BUILD / f'results-{stamp}.json'
    destination.write_text(json.dumps(report, indent=2) + '\n')
    print(f'Validated raw results: {destination}')


if __name__ == '__main__':
    main()
