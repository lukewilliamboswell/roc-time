app [main!] { pf: platform "../chrono/platform/main.roc", time: "../../package/main.roc", zones: "../../tzdb/package/main.roc" }
import pf.Host
import time.Coverage
import CoverageWorkload
import ZoneWorkload
import RecurrenceWorkload

main! = |args| {
	workload = args.get(1) ?? crash "workload required"
	if workload == "timing-control" {
		return sample!(
			{ iterations: number(args, 2), warmups: number(args, 3), samples: number(args, 4), expected: [1.U64, 2] },
			|index| index + 1,
		)
	}
	if workload.starts_with("zone-") {
		return zone!(args, workload)
	}
	if workload.starts_with("recurrence-") {
		return recurrence!(args, workload)
	}
	mode = match workload {
		"coverage-sorted" => Sorted
		"coverage-unsorted" => Unsorted
		"coverage-reject-unsorted" => RejectUnsorted
		"coverage-union" => Union
		"coverage-intersection" => Intersection
		"coverage-difference" => Difference
		"coverage-contains" => Contains
		"coverage-fold-overlap" => FoldOverlap
		"coverage-materialize-overlap" => MaterializeOverlap
		_ => crash "unknown workload"
	}
	shape = match args.get(2) {
		Ok("sparse") => Sparse
		Ok("dense") => Dense
		Ok("disjoint") => Disjoint
		_ => crash "unknown coverage profile"
	}
	count = number(args, 3)
	matches = number(args, 4)
	iterations = number(args, 5)
	warmups = number(args, 6)
	samples = number(args, 7)
	blocks = if (shape == Dense) count // 2 else count
	Host.assert!([0, 8, 4096].contains(count) and matches <= blocks and matches <= 64)
	first = CoverageWorkload.prepare({ count, shape, matches, mode, phase: 0 })
	second = CoverageWorkload.prepare({ count, shape, matches, mode, phase: 1 })
	settings = { iterations, warmups, samples, first: first.expected, second: second.expected }
	match mode {
		Sorted => sample_coverage!(settings, first.left_spans, second.left_spans, CoverageWorkload.sorted)
		Unsorted => sample_coverage!(settings, first.reversed, second.reversed, |spans| Spans(Coverage.from_spans(spans).to_spans()))
		RejectUnsorted => sample_coverage!(settings, first.reversed, second.reversed, CoverageWorkload.sorted)
		Union => sample_coverage!(settings, (first.left, first.right), (second.left, second.right), |(left, right)| Spans(Coverage.union(left, right).to_spans()))
		Intersection => sample_coverage!(settings, (first.left, first.right), (second.left, second.right), |(left, right)| Spans(Coverage.intersection(left, right).to_spans()))
		Difference => sample_coverage!(settings, (first.left, first.right), (second.left, second.right), |(left, right)| Spans(Coverage.difference({ base: left, subtract: right }).to_spans()))
		Contains => sample_coverage!(settings, (first.left, first.point), (second.left, second.point), |(coverage, point)| Point(Coverage.contains(coverage, point)))
		FoldOverlap => sample_coverage!(settings, (first.left, first.query), (second.left, second.query), CoverageWorkload.fold)
		MaterializeOverlap => sample_coverage!(settings, (first.left, first.query), (second.left, second.query), |(coverage, window)| Spans(Coverage.overlapping_spans(coverage, window)))
	}
}

CoverageSettings : { iterations : U64, warmups : U64, samples : U64, first : CoverageWorkload.Output, second : CoverageWorkload.Output }

sample_coverage! : CoverageSettings, a, a, (a -> CoverageWorkload.Output) => { bytes : List(U8), work : List(U64) }
sample_coverage! = |{ iterations, warmups, samples, first: expected_first, second: expected_second }, first, second, operation| {
	Host.assert!(operation(first) == expected_first)
	Host.assert!(operation(second) == expected_second)
	sample!(
		{ iterations, warmups, samples, expected: [CoverageWorkload.checksum(expected_first), CoverageWorkload.checksum(expected_second)] },
		|index| CoverageWorkload.checksum(operation(if (index == 0) first else second)),
	)
}

zone! = |args, workload| {
	mode = match workload {
		"zone-load" => Load
		"zone-reject-schema" => RejectSchema
		"zone-lookup" => Lookup
		"zone-offset" => Offset
		"zone-resolve" => Resolve
		_ => crash "unknown zone workload"
	}
	name = args.get(2) ?? crash "zone name required"
	scenario = args.get(3) ?? crash "zone scenario required"
	fixture = ZoneWorkload.prepare(name, scenario, mode)
	Host.assert!(ZoneWorkload.run(mode, fixture) == fixture.expected)
	expected = ZoneWorkload.checksum(fixture.expected)
	sample!(
		{ iterations: number(args, 4), warmups: number(args, 5), samples: number(args, 6), expected: [expected, expected] },
		|_index| ZoneWorkload.checksum(ZoneWorkload.run(mode, fixture)),
	)
}

recurrence! = |args, workload| {
	mode = match workload {
		"recurrence-construct" => Construct
		"recurrence-invalid-count" => InvalidCount
		"recurrence-first" => First
		"recurrence-window" => Window
		"recurrence-resume" => Resume
		_ => crash "unknown recurrence workload"
	}
	profile = args.get(2) ?? crash "series profile required"
	fixture = RecurrenceWorkload.prepare(profile, mode)
	run = |offset| RecurrenceWorkload.run(mode, { ..fixture, max_steps: fixture.max_steps + offset })
	var $expected = []
	for offset in [0.U64, 1] {
		observation = run(offset)
		Host.assert!(observation.outcome == fixture.expected)
		Host.assert!(observation.steps <= fixture.max_steps + offset and observation.buffered <= (if (mode == Window) 4 else 1))
		if observation.outcome == Limited {
			Host.assert!(observation.steps == fixture.max_steps + offset)
		}
		$expected = $expected.append(RecurrenceWorkload.checksum(observation))
	}
	sample!(
		{ iterations: number(args, 3), warmups: number(args, 4), samples: number(args, 5), expected: $expected },
		|index| RecurrenceWorkload.checksum(run(index)),
	)
}

sample! = |{ iterations, warmups, samples, expected: values }, operation| {
	Host.assert!(iterations > 0 and iterations <= 10000 and warmups <= 10 and samples <= 50)
	first = values.get(0) ?? crash "first expected checksum"
	second = values.get(1) ?? crash "second expected checksum"
	expected = (iterations // 2) * (first + second) + (iterations % 2) * first
	var $i = 0.U64
	while $i < warmups {
		Host.assert!(batch!(operation, iterations) == expected)
		$i = $i + 1
	}
	var $output = []
	$i = 0
	while $i < samples {
		start = Host.monotonic_ns!({})
		checksum = batch!(operation, iterations)
		end = Host.monotonic_ns!({})
		Host.assert!(checksum == expected and end > start)
		$output = $output.append("${(end - start).to_str()},${checksum.to_str()}")
		$i = $i + 1
	}
	{ bytes: "${expected.to_str()}\n${Str.join_with($output, "\n")}\n".to_utf8(), work: [] }
}

number = |args, index| {
	text = args.get(index) ?? crash "number required"
	U64.from_str(text) ?? crash "invalid unsigned number at ${index.to_str()}: ${Str.inspect(text)}"
}

batch! = |operation, iterations| {
	var $i = 0.U64
	var $checksum = 0.U64
	bound = Host.opaque_u64!(iterations)
	while $i < bound {
		index = Host.opaque_u64!($i % 2)
		$checksum = $checksum + Host.opaque_u64!(operation(index))
		$i = $i + 1
	}
	$checksum
}
