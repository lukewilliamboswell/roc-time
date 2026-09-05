#!/usr/bin/env python3
"""Prototype generated zone columns and measure compiler/binary costs (not a DB release)."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile
import time
import zipfile
from zoneinfo._common import load_data

sys.dont_write_bytecode = True
from generate_zone_oracle import WHEEL_SHA256

ROOT = Path(__file__).resolve().parents[1]
SELECTED = ["Australia/Melbourne", "America/New_York", "Europe/London", "Pacific/Apia"]


def execute(cmd, cwd, logs, label):
    begin = time.perf_counter()
    result = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, timeout=180)
    (logs / f"{label}.stdout").write_text(result.stdout)
    (logs / f"{label}.stderr").write_text(result.stderr)
    if result.returncode != 0:
        raise RuntimeError(f"{label} failed ({result.returncode}): {result.stderr[:2000]} {result.stdout[:1000]}")
    return result, time.perf_counter() - begin


def export(destination, entries):
    destination.mkdir()
    unique, names = {}, {}
    for name, raw in entries.items():
        key = hashlib.sha256(raw).hexdigest()
        if key not in unique:
            module = f"Z{len(unique):03}"
            indices, times, offsets, _, _, footer = load_data(io.BytesIO(raw))
            payload = dict(times=list(times), indices=list(indices), offsets=list(offsets), footer=(footer or b"").decode())
            unique[key] = module, payload
            fields = ", ".join(f"{field}: {json.dumps(value)}" for field, value in payload.items())
            destination.joinpath(f"{module}.roc").write_text(f'{module} :: [].{{\n data : {{ times : List(I64), indices : List(U8), offsets : List(I32), footer : Str }}\n data = {{ {fields} }}\n}}\n')
        names[name] = unique[key]
    imports = "".join(f"import {module}\n" for module, _ in unique.values())
    matches = "".join(f'  {json.dumps(name)} => Ok({module}.data)\n' for name, (module, _) in sorted(names.items()))
    destination.joinpath("Lookup.roc").write_text(imports + "Lookup :: [].{\n get = |name| match name {\n" + matches + '  _ => Err(UnknownZone(name))\n }\n}\n')
    melbourne = names["Australia/Melbourne"][0]
    destination.joinpath("Melbourne.roc").write_text(f"import {melbourne}\nMelbourne :: [].{{ data = {melbourne}.data }}\n")
    destination.joinpath("main.roc").write_text("package [Lookup, Melbourne] {}\n")
    return names


def main(wheel, samples):
    if platform.python_implementation() != "CPython" or platform.python_version() != "3.14.3":
        raise SystemExit("Requires pinned CPython 3.14.3 TZif decoder")
    if hashlib.sha256(wheel.read_bytes()).hexdigest() != WHEEL_SHA256:
        raise SystemExit("Wrong tzdata wheel")
    roc = str(Path(os.environ["ROC"]).resolve())
    tmp = ROOT / ".roc-time-tmp"
    tmp.mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="zone-roc-measure-", dir=tmp))
    version, _ = execute([roc, "version"], work, work, "version")
    if version.stdout.strip() != "Roc compiler version " + (ROOT / ".roc-version").read_text().strip():
        raise SystemExit("Wrong Roc compiler")
    entries = {}
    with zipfile.ZipFile(wheel) as archive:
        for info in archive.infolist():
            if info.filename.startswith("tzdata/zoneinfo/") and not info.is_dir():
                raw = archive.read(info)
                if raw.startswith(b"TZif"):
                    entries[info.filename.removeprefix("tzdata/zoneinfo/")] = raw
    global_names = export(work / "global", entries)
    subset_names = export(work / "subset", {name: entries[name] for name in SELECTED})
    report = {"compiler": version.stdout.strip(), "host": platform.platform(), "wheel_sha256": WHEEL_SHA256,
              "samples": samples, "representation": "one module per byte-distinct TZif; times I64, indices U8, offsets I32, footer Str; dynamic match lookup with aliases",
              "limits": "Prototype columns only, not a full provider or TZif adapter. No footer expansion, schema import, construction allocation or retained-memory measurement. OS/compiler caches may be warm; --no-cache disables Roc cache for uncached builds. Native default backend only.",
              "packages": {}, "applications": {}}
    for kind in ["global", "subset"]:
        directory = work / kind
        sources = sorted(directory.glob("*.roc"))
        bundle_dir = directory / "bundle"
        bundle_dir.mkdir()
        output, _ = execute([roc, "bundle", *[p.name for p in sources], "--output-dir", str(bundle_dir)], directory, work, f"bundle-{kind}")
        bundle = next(bundle_dir.glob("*.tar.zst"))
        report["packages"][kind] = {"roc_source_bytes": sum(p.stat().st_size for p in sources), "bundle_bytes": bundle.stat().st_size, "module_count": len(sources)}
    app_body = '''main! = |args| {
 var name = "Australia/Melbourne"
 for arg in args { name = arg }
 PAYLOAD
 var checksum = name.count_utf8_bytes().to_i64_wrap()
 for second in data.times { checksum = I64.rem_by(checksum + I64.rem_by(second, 1000003), 1000003) }
 for index in data.indices { checksum = I64.rem_by(checksum + index.to_i64(), 1000003) }
 for offset in data.offsets { checksum = I64.rem_by(checksum + offset.to_i64(), 1000003) }
 echo!("${data.times.len().to_str()}|${checksum.to_str()}|${data.footer}\\n")
 Ok({})
}
'''
    for kind in ["core_only", "static_global", "dynamic_global", "dynamic_subset"]:
        app = work / kind
        app.mkdir()
        if kind == "core_only":
            package_path = os.path.relpath(ROOT / "package/main.roc", app)
            source = f'app [main!] {{ time: "{package_path}" }}\nimport time.PosixBoundary\nmain! = |_args| {{ echo!(Str.inspect(PosixBoundary.from_microseconds(42)))\n Ok({{}}) }}\n'
        else:
            package = "subset" if kind == "dynamic_subset" else "global"
            module = "Melbourne" if kind == "static_global" else "Lookup"
            source = f'app [main!] {{ db: "../{package}/main.roc" }}\nimport db.{module}\n' + app_body.replace("PAYLOAD", "data = Melbourne.data" if kind == "static_global" else "data = Lookup.get(name)?")
        app.joinpath("main.roc").write_text(source)
        execute([roc, "check", "main.roc"], app, work, f"check-{kind}")
        measurements = []
        for sample in range(samples):
            binary = app / "native"
            command = [roc, "build", "main.roc", "--no-cache", f"--output={binary}"]
            if sys.platform == "darwin":
                command = ["/usr/bin/time", "-l", *command]
            result, elapsed = execute(command, app, work, f"build-{kind}-{sample}")
            rss = re.search(r"(\d+)\s+maximum resident set size", result.stderr)
            measurements.append({"seconds": elapsed, "compiler_peak_rss_bytes": int(rss[1]) if rss else None, "binary_bytes": binary.stat().st_size})
        outputs = {}
        for name in (["Australia/Melbourne"] if kind in ["core_only", "static_global"] else SELECTED):
            result, _ = execute([str(app / "native"), name], app, work, f"run-{kind}-{name.replace('/', '-')}")
            if kind != "core_only":
                payload = (subset_names if kind == "dynamic_subset" else global_names)[name][1]
                # Roc rem_by truncates toward zero; reproduce its sign convention.
                def rem(n): return n % 1000003 if n >= 0 else -((-n) % 1000003)
                checksum = len(name.encode())
                for n in payload["times"]: checksum = rem(checksum + rem(n))
                for n in payload["indices"] + payload["offsets"]: checksum = rem(checksum + n)
                expected = f'{len(payload["times"])}|{checksum}|{payload["footer"]}\n'
                if result.stdout != expected:
                    raise RuntimeError(f"Observable checksum mismatch {kind} {name}: {result.stdout!r} != {expected!r}")
            outputs[name] = result.stdout.strip()
        report["applications"][kind] = {"uncached_builds": measurements, "observable_outputs": outputs}
        (work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"Measured {kind}: {measurements}", flush=True)
    print(f"Evidence: {work / 'report.json'}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wheel", type=Path)
    parser.add_argument("--samples", type=int, default=3)
    args = parser.parse_args()
    if not 1 <= args.samples <= 10: parser.error("samples must be 1..10")
    main(args.wheel, args.samples)
