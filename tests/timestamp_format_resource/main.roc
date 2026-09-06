app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.OffsetTimestamp
import FormatFixture

# R01/R14/R15/R16: parse/validation and input storage precede counters.
# The scoped totals count formatter allocation/reallocation requests, not live
# bytes. Exact output equality observes every byte without allocating a checksum
# buffer for short strings. Stored scalar declarations have no heap fields.
main! = |args| {
	count = U64.from_str(args.get(1) ?? "32000") ?? 32000
	year = args.get(2) ?? "0000"
	shared = (args.get(3) ?? "shared") == "shared"
	ceiling = U64.from_str(args.get(4) ?? "1") ?? 1
	Host.assert!(count > 0 and count <= 32000 and (year == "0000" or year == "9999"))
	input = FormatFixture.make(year)
	retained = if shared {
		Some(input.values)
	} else {
		None
	}
	before_calls = Host.allocation_count!({})
	before_bytes = Host.allocated_bytes!({})
	var i = 0.U64
	var length = 0.U64
	while i < count {
		index = U64.rem_by(i, input.values.len())
		value = match input.values.get(index) {
			Ok(v) => v
			Err(_) => crash "corpus index"
		}
		expected = match input.texts.get(index) {
			Ok(v) => v
			Err(_) => crash "expected index"
		}
		text = OffsetTimestamp.to_text(value)
		Host.assert!(text == expected)
		length = length + text.count_utf8_bytes()
		i = i + 1
	}
	after_calls = Host.allocation_count!({})
	after_bytes = Host.allocated_bytes!({})
	Host.assert!(after_calls - before_calls <= count * ceiling and after_bytes - before_bytes <= count * 128 and length >= count * 20)
	match retained {
		Some(values) => {
			first = match values.get(0) {
				Ok(v) => v
				Err(_) => crash "retained first"
			}
			last = match values.get(20) {
				Ok(v) => v
				Err(_) => crash "retained last"
			}
			Host.assert!(OffsetTimestamp.to_text(first) == "${year}-01-02T03:04:05Z" and OffsetTimestamp.to_text(last) == "${year}-01-02T03:04:05.000006-12:45")
		}
		None => {}
	}
	{ bytes: "format=canonical,width=preserved,assertion=preserved\n".to_utf8(), work: [after_calls - before_calls, after_bytes - before_bytes, length] }
}
