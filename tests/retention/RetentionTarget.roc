import fuzz.Fuzz
import time.Coverage
import time.PosixBoundary
import time.PosixSpan
import time.ZoneRules
import zones.Database

RetentionTarget := [].{
	target = Fuzz.target_with!({
		name: "retention-v1",
		examples: [
			Fuzz.example({ name: "coverage-empty", revision: "1", make: || 0.U8 }),
			Fuzz.example({ name: "coverage-small", revision: "1", make: || 1.U8 }),
			Fuzz.example({ name: "coverage-large", revision: "1", make: || 2.U8 }),
			Fuzz.example({ name: "new-york", revision: "1", make: || 3.U8 }),
			Fuzz.example({ name: "lord-howe", revision: "1", make: || 4.U8 }),
		],
		generator: Fuzz.u8_in(0, 4),
		test!,
		show: Str.inspect,
	})
}

test! = |scenario| {
	match scenario {
		0 => coverage!(0)
		1 => coverage!(8)
		2 => coverage!(4096)
		3 => zone!("America/New_York", 560)
		_ => zone!("Australia/Lord_Howe", 439)
	}
	Fuzz.keep
}

# R04/R15. Leave the caller's slice alive across the measurement. Spans are
# disjoint by construction and remain in the same order in the output.
coverage! : U64 => {}
coverage! = |count| {
	var $backing = List.with_capacity(count + 2)
	var $index = 0.U64
	while $index < count + 2 {
		start = $index.to_i64_wrap() * 4
		span = PosixSpan.new({
			start: PosixBoundary.from_microseconds(start),
			end: PosixBoundary.from_microseconds(start + 2),
		}) ?? crash "disjoint bounded span"
		$backing = $backing.append(span)
		$index = $index + 1
	}
	slice = $backing.sublist({ start: 1, len: count })
	observed = Fuzz.measure!(
		"sorted coverage retained",
		|| {
			coverage = Coverage.from_sorted_spans(slice) ?? crash "sorted fixture"
			{ slice, coverage }
		},
	)
	if Coverage.to_spans(observed.value.coverage) != observed.value.slice or
		Coverage.member_count(observed.value.coverage) != count or $backing.len() != count + 2 {
		crash "retained slice or canonical output changed"
	}
	# Allow a geometrically grown flat output buffer. The baseline records the
	# exact observed delta independently of cumulative allocation requests.
	check_growth!(observed.stats, count * 32 + 256)
}

# R07/R15. Database.get is outside admission. Keep both the fixture record and
# admitted rules alive through the checkpoint and observe their table lengths.
zone! : Str, U64 => {}
zone! = |name, count| {
	data = Database.get(name) ?? crash "pinned IANA fixture"
	observed = Fuzz.measure!(
		"loaded rules retained",
		|| {
			rules = ZoneRules.from_database(data) ?? crash "valid pinned fixture"
			{ data, rules }
		},
	)
	definition = ZoneRules.definition(observed.value.rules)
	if definition.transitions.len() != count or observed.value.data.transitions.len() != count {
		crash "pinned 2026e transition count changed"
	}
	check_growth!(observed.stats, count * 64 + 256)
}

check_growth! : Fuzz.Stats, U64 => {}
check_growth! = |stats, allowance| {
	if stats.exit_live_bytes < stats.entry_live_bytes or
		stats.exit_live_bytes - stats.entry_live_bytes > allowance {
		crash "retained live bytes outside workload bound: ${Str.inspect(stats)}"
	}
}
