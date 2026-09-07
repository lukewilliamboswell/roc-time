app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.Coverage
import IdentityFixture

# R04/R15: construction and exact semantic checks are outside each measured
# operation. Counters observe allocation/reallocation traffic, not retained size.
main! = |args| {
	count = U64.from_str(args.get(1) ?? "4096") ?? 4096
	operation = args.get(2) ?? "union_right"
	control = args.get(3) ?? "normal"
	Host.assert!(count <= 4096)
	inputs = [IdentityFixture.make(count, 0), IdentityFixture.make(count, 1)]
	retained = inputs
	var $i = 0.U64
	var $bytes = 0.U64
	var $calls = 0.U64
	while $i < 12 {
		index = Host.opaque_u64!($i) % 2
		source = inputs.get(index) ?? crash "bounded index"
		before_bytes = Host.allocated_bytes!({})
		before_calls = Host.allocation_count!({})
		result = if operation == "union_right" {
			Coverage.union(source, Coverage.empty)
		} else if operation == "union_left" {
			Coverage.union(Coverage.empty, source)
		} else {
			Host.assert!(operation == "difference_right")
			Coverage.difference(source, Coverage.empty)
		}
		if control == "allocate" {
			allocated = List.with_capacity(Host.opaque_u64!(64)).append(index)
			Host.assert!(allocated.get(0) == Ok(index))
		}
		after_bytes = Host.allocated_bytes!({})
		after_calls = Host.allocation_count!({})
		$bytes = $bytes + after_bytes - before_bytes
		$calls = $calls + after_calls - before_calls
		Host.assert!(result == source)
		Host.assert!(Coverage.to_spans(result) == Coverage.to_spans(IdentityFixture.make(count, index.to_i64_wrap())))
		$i = $i + 1
	}
	Host.assert!(retained == inputs)
	Host.assert!($bytes == 0 and $calls == 0)
	{ bytes: "coverage-identity=preserved\n".to_utf8(), work: [$bytes, $calls] }
}
