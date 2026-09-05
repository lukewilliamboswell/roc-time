import CalendarDate
import ClockTime
import FixedOffset
import LocalDateTime
import PosixBoundary
import PosixSpan
import ZoneRules

## Independent bounded timeline enumeration for R07 classification.
ZoneRulesTests :: [].{
	expect {
		span = PosixSpan.new(point(-10000000), point(10000000))?
		bad_bounds = match ZoneRules.new_bounded("Synthetic", "v1", span, FixedOffset.from_seconds(0), [], { minimum: 1, maximum: -1 }) {
			Err(InvalidOffsetBounds) => Bool.True
			_ => Bool.False
		}
		bad_initial = match ZoneRules.new_bounded("Synthetic", "v1", span, FixedOffset.from_seconds(3), [], { minimum: -2, maximum: 2 }) {
			Err(OffsetOutsideBounds) => Bool.True
			_ => Bool.False
		}
		bad_transition = match ZoneRules.new_bounded("Synthetic", "v1", span, FixedOffset.from_seconds(0), [{ at: point(0), offset: FixedOffset.from_seconds(-3) }], { minimum: -2, maximum: 2 }) {
			Err(OffsetOutsideBounds) => Bool.True
			_ => Bool.False
		}
		bad_bounds and bad_initial and bad_transition
	}

	expect {
		var valid = Bool.True
		for first in [-2.I32, 0, 2] {
			for second in [-2.I32, 0, 2] {
				span = PosixSpan.new(point(-10000000), point(10000000))?
				rules = ZoneRules.new_bounded(
					"Synthetic/Enumeration",
					"v1",
					span,
					FixedOffset.from_seconds(0),
					[
						{ at: point(0), offset: FixedOffset.from_seconds(first) },
						{ at: point(4000000), offset: FixedOffset.from_seconds(second) },
					],
					{ minimum: -2, maximum: 2 },
				)?
				var local_second = -7.I64
				while local_second <= 7 {
					for fraction in [0.I64, 1, 999999] {
						number = local_second * 1000000 + fraction
						local = local_label(number)?
						var expected = []
						var timeline_second = -10.I64
						while timeline_second < 10 {
							# Direct synthetic fixture definition, independent of
							# transition iteration and inverse offset conversion.
							offset = if timeline_second < 0 {
								0.I32
							} else if timeline_second < 4 {
								first
							} else {
								second
							}
							if timeline_second + offset.to_i64() == local_second {
								expected = expected.append(point(timeline_second * 1000000 + fraction))
							}
							timeline_second = timeline_second + 1
						}
						classification = match expected {
							[] => Gap
							[only] => Unique(only)
							_ => Fold(expected)
						}
						valid = valid and ZoneRules.resolve(rules, local) == Ok(classification)
					}
					local_second = local_second + 1
				}
				# Even if an in-table match exists, unknown outside rules can
				# supply another candidate. Never claim uniqueness at this edge.
				edge = local_label(-9000000)?
				valid = valid and ZoneRules.resolve(rules, edge) == Err(OutsideValidity)
			}
		}
		valid
	}

	expect {
		span = PosixSpan.new(point(-10000000), point(10000000))?
		rules = ZoneRules.new_bounded(
			"Synthetic/Triple",
			"v1",
			span,
			FixedOffset.from_seconds(4),
			[
				{ at: point(0), offset: FixedOffset.from_seconds(2) },
				{ at: point(1000000), offset: FixedOffset.from_seconds(0) },
			],
			{ minimum: 0, maximum: 4 },
		)?
		local = local_label(2500000)?
		ZoneRules.resolve(rules, local) == Ok(Fold([point(-1500000), point(500000), point(2500000)]))
	}
}

point = |number| PosixBoundary.from_microseconds(number)

# Test labels near epoch are formed directly from calendar fields and clock
# positions; do not use FixedOffset.project as an inverse-resolution oracle.
local_label = |number| {
	fields = if number < 0 {
		{ year: 1969.I64, month: 12.U8, day: 31.U8 }
	} else {
		{ year: 1970.I64, month: 1.U8, day: 1.U8 }
	}
	date = CalendarDate.from_fields(Gregorian, fields)?
	clock = ClockTime.from_microseconds_since_midnight(
		if number < 0 {
			number + 86400000000
		} else {
			number
		},
	)?
	Ok(LocalDateTime.new(date, clock))
}
