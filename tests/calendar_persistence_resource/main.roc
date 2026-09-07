app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.Persistence
import time.CalendarValue
import time.QualifiedCalendarValue
import time.CalendarDate
import time.ClockTime
import time.LocalDateTime
import CalendarFixture

# R13/R14/R15: values at the Julian provider limit stay symbolic; persistence
# must not lower the selection's exclusive end or resolve a timeline. Runtime
# inputs and invalid framing are built outside measured scopes. Traffic counts
# allocation requests, not live memory. Shared source values remain observable.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	digits = U8.from_str(args.get(1) ?? "6") ?? 6
	all = (args.get(2) ?? "8") == "8"
	ceiling = U64.from_str(args.get(3) ?? "65536") ?? 65536
	year = I64.from_str(args.get(4) ?? "2147483647") ?? 2147483647
	Host.assert!(digits >= 1 and digits <= 6 and (year == 2004 or year == 2147483647))
	value = CalendarFixture.value(year, digits)
	qualified = CalendarFixture.qualified(value, all)
	native = match Persistence.new(CalendarValue(value)) {
		Ok(v) => v
		Err(_) => crash "native persistence"
	}
	marked = match Persistence.new(QualifiedCalendarValue(qualified)) {
		Ok(v) => v
		Err(_) => crash "qualified persistence"
	}
	before = Host.allocated_bytes!({})
	text = Persistence.to_text(native)
	serialized = Host.allocated_bytes!({})
	decoded = match Persistence.parse(text) {
		Ok(v) => v
		Err(_) => crash "native restore"
	}
	parsed = Host.allocated_bytes!({})
	Host.assert!(serialized - before <= ceiling and parsed - serialized <= ceiling)
	observed = match Persistence.value(decoded) {
		CalendarValue(v) => v
		_ => crash "wrong native variant"
	}
	fields = CalendarDate.to_fields(LocalDateTime.date(CalendarValue.start_label(observed)))
	clock = ClockTime.to_fields(LocalDateTime.clock(CalendarValue.start_label(observed)))
	var $expected_fraction = 1.U32
	var $places = 6.U8 - digits
	while $places > 0 {
		$expected_fraction = $expected_fraction * 10
		$places = $places - 1
	}
	Host.assert!(fields == { year, month: 12, day: 31 } and CalendarDate.calendar(LocalDateTime.date(CalendarValue.start_label(observed))) == Julian and CalendarValue.resolution(observed) == Fraction(digits) and clock == { hour: 23, minute: 59, second: 59, microsecond: 1000000 - $expected_fraction })
	if year == 2147483647 {
		Host.assert!(CalendarValue.local_bounds(observed) == Err(OutOfRange))
	}
	marked_before = Host.allocated_bytes!({})
	marked_text = Persistence.to_text(marked)
	marked_serialized = Host.allocated_bytes!({})
	marked_decoded = match Persistence.parse(marked_text) {
		Ok(v) => v
		Err(_) => crash "qualified restore"
	}
	marked_parsed = Host.allocated_bytes!({})
	Host.assert!(marked_serialized - marked_before <= ceiling and marked_parsed - marked_serialized <= ceiling and Persistence.value(marked_decoded) == QualifiedCalendarValue(qualified))
	Host.assert!(
		QualifiedCalendarValue.qualifications(qualified).len() == (
			if all {
				8
			} else {
				0
			}
		),
	)
	oversized = CalendarFixture.envelope("calendar-value", "native-calendar-value-v1", "x".repeat(1025))
	excessive = CalendarFixture.envelope("qualified-calendar-value", "native-qualified-calendar-value-v1", "julian;fraction;2004;12;31;23;59;59;6;1|${Str.join_with(List.repeat("whole=uncertain", 9), ";")}")
	invalid_before = Host.allocated_bytes!({})
	large_result = Persistence.parse(oversized)
	large_after = Host.allocated_bytes!({})
	excessive_result = Persistence.parse(excessive)
	excessive_after = Host.allocated_bytes!({})
	Host.assert!(large_result == Err(InvalidCalendarValue(TooLarge)) and excessive_result == Err(InvalidQualifiedCalendarValue(TooManyQualifications)) and large_after - invalid_before <= ceiling and excessive_after - large_after <= ceiling)
	{ bytes: "calendar=preserved,qualifications=preserved,limits=rejected\n".to_utf8(), work: [serialized - before, parsed - serialized, marked_serialized - marked_before, marked_parsed - marked_serialized, large_after - invalid_before, excessive_after - large_after] }
}
