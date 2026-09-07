app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.GregorianDate
import QueryFixture

# R05/R15/R16. Input construction traffic and scalar query traffic are separate.
# Counters measure requested allocation bytes, not live or retained memory.
main! = |args| {
	count = U64.from_str(args.get(1) ?? "32000") ?? 32000
	ownership = args.get(2) ?? "shared"
	control = (args.get(3) ?? "normal") == "control"
	Host.assert!(count > 0 and count <= 32000)
	normal_output = "queries=exact\n".to_utf8()
	construction_calls = Host.allocation_count!({})
	construction_bytes = Host.allocated_bytes!({})
	backing = QueryFixture.make(count + 2)
	retained = if ownership == "owned" {
		None
	} else {
		Some(backing)
	}
	shift = if ownership == "sliced" {
		1.U64
	} else {
		0.U64
	}
	values = backing.sublist({ start: shift, len: count })
	before_calls = Host.allocation_count!({})
	before_bytes = Host.allocated_bytes!({})
	var $sum = 0.U64
	for date in values {
		fields = GregorianDate.to_fields(date)
		ordinal = GregorianDate.ordinal_day(date)
		weekday = GregorianDate.weekday(date)
		week = GregorianDate.iso_week_date(date)
		# Fixed fixtures include ISO-year crossings and both provider endpoints.
		expected = QueryFixture.expected(fields.year, fields.month, fields.day)
		Host.assert!(ordinal == expected.ordinal and weekday == expected.weekday and week.weekday == weekday and week.week_year == expected.year and week.week == expected.week)
		$sum = $sum + ordinal.to_u64() + week.week.to_u64()
	}
	# Keep a deliberately allocated result observable to prove the zero-allocation
	# assertion remains active under optimization.
	bytes = if control {
		ownership.repeat(64).to_utf8()
	} else {
		normal_output
	}
	after_calls = Host.allocation_count!({})
	after_bytes = Host.allocated_bytes!({})
	Host.assert!(after_calls == before_calls and after_bytes == before_bytes)
	match retained {
		Some(original) => {
			Host.assert!(original.len() == count + 2)
			Host.assert!(original.get(0) == GregorianDate.from_fields({ year: 2020, month: 12, day: 31 }))
		}
		None => {}
	}
	{ bytes, work: [before_calls - construction_calls, before_bytes - construction_bytes, after_calls - before_calls, after_bytes - before_bytes, $sum] }
}
