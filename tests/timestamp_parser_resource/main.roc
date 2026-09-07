app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.OffsetTimestamp
import time.PosixBoundary

# R01/R14/R15: argument preparation and deliberate retained inputs are outside
# the counters. Each parse selects runtime inputs using a hosted opaque index.
# Mode names describe input preparation, not verified backing layouts. Allocation traffic is not live memory or elapsed time.
main! = |args| {
	text = args.get(1) ?? "1970-01-01T00:00:01Z"
	mode = args.get(2) ?? "direct"
	control = args.get(3) ?? "normal"
	(input, held) = if mode == "suffix" {
		parent = "prefix:${text}"
		(parent.drop_prefix("prefix:"), [parent])
	} else if mode == "aliases" {
		(text, [text, text])
	} else {
		(text, [])
	}
	alternate = args.get(4) ?? crash "second runtime timestamp required"
	inputs = [input, alternate]
	before = Host.allocated_bytes!({})
	count_before = Host.allocation_count!({})
	var $index = 0.U64
	while $index < 1000 {
		opaque_index = Host.opaque_u64!($index)
		selected = inputs.get(opaque_index % 2) ?? crash "bounded runtime index"
		value = OffsetTimestamp.parse(selected) ?? crash "valid runtime timestamp"
		Host.assert!(OffsetTimestamp.boundary(value) == Ok(PosixBoundary.from_microseconds(1000000)))
		$index = $index + 1
	}
	if control == "allocate" {
		bytes = input.to_utf8()
		Host.assert!(bytes.len() == input.count_utf8_bytes())
	}
	after = Host.allocated_bytes!({})
	count_after = Host.allocation_count!({})
	Host.assert!(after == before and count_after == count_before)
	for retained in held {
		Host.assert!(retained == input or retained == "prefix:${input}")
	}
	{ bytes: "timestamp-parser=1000,boundary=1000000\n".to_utf8(), work: [after - before, count_after - count_before] }
}
