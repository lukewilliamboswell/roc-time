#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import cli.OsStr
import cli.Path
import src/BenchmarkOptions
import src/BenchmarkProcess
import src/ChronoBenchmark
import src/Script

main! = |args| {
	if args.map(OsStr.display) == ["--help"] {
		return Script.info!("usage:", "blueprint run benchmark-chrono -- [--fetch] [--smoke] [--iterations N] [--warmups N] [--samples N] [--roc-opt dev|speed] [--profile MODE] [--debug] [--argv0 NAME]")
	}
	options = BenchmarkOptions.parse(args.map(OsStr.display))?
	context = ChronoBenchmark.prepare!(options)?
	if !options.profile.is_empty() {
		if Script.command("uname").output!(["-s"])? != "Linux" {
			return Err(ProfilingRequiresLinuxPerf)
		}
		stamp = Script.command("date").output!(["-u", "+%Y%m%dT%H%M%S.%NZ"])?
		prefix = "perf-${options.profile}-${stamp}"
		recording = Path.join(context.work, "${prefix}.data")
		command = ["perf", "record", "-e", "cycles:u", "-F", "999", "--call-graph", "dwarf", "-o", Path.display(recording), "--", "env", "--argv0=${options.argv0}", Path.display(context.roc_binary), options.profile, options.iterations.to_str(), options.warmups.to_str(), options.samples.to_str()].concat(context.reference.cases.map(|case| case.text))
		output = BenchmarkProcess.run!(command, context.root, context.work, "${prefix}.run", [], 180000)?
		_ = BenchmarkOptions.samples(output.stdout, options.samples, context.reference.checksums.get(options.profile)?)?
		_ = BenchmarkProcess.run!(["perf", "report", "--stdio", "--no-children", "--sort", "symbol,srcline", "-i", Path.display(recording)], context.root, context.work, "${prefix}.report", [], 180000)?
		return Script.info!("PROFILE", "validated checksums; ${Path.display(recording)}; launcher startup is outside the kernel")
	}
	var $results = []
	for (mode, index) in BenchmarkOptions.modes.map_with_index(|mode, index| (mode, index)) {
		binaries = [("roc-time", context.roc_binary), ("chrono", context.rust_binary)]
		for (name, binary) in if (U64.rem_by(index, 2) == 0) binaries else [("chrono", context.rust_binary), ("roc-time", context.roc_binary)] {
			output = ChronoBenchmark.execute!(context, binary, options.argv0, mode, options.iterations, options.warmups, options.samples, "${mode}-${name}")?
			elapsed = BenchmarkOptions.samples(output.stdout, options.samples, context.reference.checksums.get(mode)?)?
			value = BenchmarkOptions.median(elapsed)? / options.iterations.to_f64()
			$results = $results.append({ library: name, workload: mode, nanoseconds: elapsed, median_ns_per_operation: value })
			Script.info!(name, "${mode}: ${value.to_str()} ns/op${if (options.smoke) " (smoke; not performance evidence)" else ""}")?
		}
	}
	report = { scope: "microsecond Gregorian fixed-offset intersection; no general library ranking", options, roc_version: context.roc_version, rustc: context.rustc, rust_pin: context.rust_pin, cargo: context.cargo, zig: Script.command(OsStr.from_str(Script.env_str!("ZIG") ?? "zig")).output!(["version"])?, machine: Script.command("uname").output!(["-s", "-r", "-m"])?, processor: Script.command("uname").output!(["-p"])?, roc_target: context.target, rust_target: context.rust_target, allocators: { roc_allocator: "libc via fixture ABI with header/counters; Zig ReleaseFast host, debug symbols retained", rust: "Rust System allocator (libc)" }, corpus_sha256: hash!("benchmarks/chrono/corpus.jsonl")?, cargo_lock_sha256: hash!("benchmarks/chrono/Cargo.lock")?, reference_adapter_sha256: hash!("scripts/reference_benchmarks.py")?, runner_sha256: hash!("scripts/benchmark_chrono.roc")?, git_revision: Script.command("git").output!(["rev-parse", "HEAD"])?, working_tree: Script.command("git").output!(["status", "--short"])?, results: $results }
	stamp = Script.command("date").output!(["-u", "+%Y%m%dT%H%M%S.%NZ"])?
	destination = Path.join(context.work, "results-${options.roc_opt}-${stamp}.json")
	Path.write_utf8!(destination, Json.to_str_try(report)?)?
	Script.info!("EVIDENCE", Path.display(destination))
}

hash! = |path| Script.command("sha256sum").output!([path])?.split_on(" ").first()
