app [main!] { pf: platform "platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import Benchmark

main! = |args| {
	mode = args.get(1) ?? "roundtrip"
	iterations = U64.from_str(args.get(2) ?? "100000") ?? 100000
	warmups = U64.from_str(args.get(3) ?? "3") ?? 3
	samples = U64.from_str(args.get(4) ?? "7") ?? 7
	Host.assert!(iterations > 0 and iterations <= 10000000 and warmups <= 10 and samples <= 50 and args.len() > 5)
	data = Benchmark.prepare(args.sublist({ start: 5, len: args.len() - 5 }))
	if mode == "verify" {
		return { bytes: "${Benchmark.verify(data)}\n".to_utf8(), work: [] }
	}
	# Dispatch before warmups and timestamp reads; each call supplies a fixed kernel.
	match mode {
		"date_control" => sample!(data.map(|v| v.date), iterations, warmups, samples, Benchmark.date_control)
		"date_to_day" => sample!(data.map(|v| v.date), iterations, warmups, samples, Benchmark.date_to_day)
		"construct" => sample!(data.map(|v| v.fields), iterations, warmups, samples, Benchmark.construct)
		"roundtrip" => sample!(data.map(|v| v.date), iterations, warmups, samples, Benchmark.roundtrip)
		"add_days" => sample!(data.map(|v| v.date), iterations, warmups, samples, Benchmark.add_days)
		"parse" => sample!(data.map(|v| v.text), iterations, warmups, samples, Benchmark.parse)
		"resolve" => sample!(data.map(|v| v.timestamp), iterations, warmups, samples, Benchmark.resolve)
		"format" => sample!(data.map(|v| v.timestamp), iterations, warmups, samples, Benchmark.format)
		"end_to_end" => sample!(data.map(|v| v.text), iterations, warmups, samples, Benchmark.end_to_end)
		_ => crash "unknown workload"
	}
}

sample! = |data, iterations, warmups, samples, operation| {
	# Monotonicity and allocation-free observation checked outside measurements.
	clock_alloc = Host.allocated_bytes!({})
	clock_start = Host.monotonic_ns!({})
	clock_end = Host.monotonic_ns!({})
	Host.assert!(clock_end >= clock_start and Host.allocated_bytes!({}) == clock_alloc)
	var i = 0.U64
	var checksum = 0.U64
	while i < warmups {
		checksum = Host.opaque_u64!(Benchmark.run(data, Host.opaque_u64!(iterations), operation))
		Host.assert!(checksum > 0)
		i = i + 1
	}
	var output = []
	i = 0
	while i < samples {
		start = Host.monotonic_ns!({})
		checksum = Host.opaque_u64!(Benchmark.run(data, Host.opaque_u64!(iterations), operation))
		end = Host.monotonic_ns!({})
		Host.assert!(end >= start)
		output = output.append("${(end - start).to_str()},${checksum.to_str()}")
		i = i + 1
	}
	{ bytes: "${Str.join_with(output, "\n")}\n".to_utf8(), work: [] }
}
