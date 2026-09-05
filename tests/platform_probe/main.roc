app [main!] {
	pf: platform "../platform/main.roc",
	time: "../../package/main.roc",
}
import pf.Host
import ResourceProbe

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	input = args.get(1) ?? "42"
	value = I64.from_str(input) ?? 42
	other = I64.from_str(args.get(2) ?? "43") ?? 43
	allocation_before = Host.allocation_count!({})
	retained = input.repeat(64)
	allocation_after = Host.allocation_count!({})
	Host.assert!(allocation_after > allocation_before)
	before = Host.allocation_count!({})
	Host.mark!(1)
	comparison = ResourceProbe.compare(value, other)
	same = comparison == (
		if value < other {
			0
		} else if value == other {
			1
		} else {
			2
		}
	)
	traffic = Host.allocated_bytes!({})
	_frees = Host.deallocation_count!({})
	Host.mark!(2)
	after = Host.allocation_count!({})
	expect same
	expect after == before
	Host.assert!(same and after == before)
	if input == "fail-assert" {
		Host.assert!(False)
	}
	if input == "fail-expect" {
		expect False
	}
	{ bytes: retained.to_utf8(), work: [after - before, comparison, traffic] }
}
