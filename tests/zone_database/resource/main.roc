app [main!] {
	pf: platform "../../platform/main.roc",
	db: "../../../tzdb/package/main.roc",
}
import pf.Host
import db.Database

# Runtime names and consumed transitions prevent a constant-result benchmark.
# The allocation bound covers lookup/record return, not core adaptation,
# retained memory, output formatting or a claim about arbitrary future pins.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	name = args.get(1) ?? "Australia/Melbourne"
	before = Host.allocation_count!({})
	Host.mark!(1)
	data = match Database.get(name) {
		Ok(value) => value
		Err(_) => crash "Unknown resource fixture zone"
	}
	Host.mark!(2)
	after = Host.allocation_count!({})
	Host.assert!(after - before <= 1)
	var checksum = 0.I64
	var index = 1.I64
	for transition in data.transitions {
		checksum = checksum + index * (transition.second + transition.offset.to_i64())
		index = index + 1
	}
	{ bytes: "${data.canonical_name}|${checksum.to_str()}\n".to_utf8(), work: [after - before, data.transitions.len()] }
}
