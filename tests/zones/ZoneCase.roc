import fuzz.Fuzz
import time.CalendarDate
import time.ClockTime
import time.Coverage
import time.FixedOffset
import time.LocalDateTime
import time.PosixBoundary
import time.PosixSpan
import time.ZoneRules
import time.ResolvedBoundary
import time.ResolvedSelection

ZoneCase := { number : I64, first : I32, second : I32 }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(ZoneCase)
	generator_for = |_| {
		number: Fuzz.map(Fuzz.u64_in(0, 14000000), |n| n.to_i64_wrap() - 7000000),
		first: Fuzz.map(Fuzz.u8_in(0, 4), |n| n.to_i32() - 2),
		second: Fuzz.map(Fuzz.u8_in(0, 4), |n| n.to_i32() - 2),
	}.Fuzz

	check : ZoneCase -> Fuzz.Outcome
	check = |input| {
		date_fields = if input.number < 0 {
			{ year: 1969.I64, month: 12.U8, day: 31.U8 }
		} else {
			{ year: 1970.I64, month: 1.U8, day: 1.U8 }
		}
		date = match CalendarDate.from_fields(Gregorian, date_fields) {
			Ok(value) => value
			Err(_) => crash "fixture date rejected"
		}
		clock = match ClockTime.from_microseconds_since_midnight(
			if input.number < 0 {
				input.number + 86400000000
			} else {
				input.number
			},
		) {
			Ok(value) => value
			Err(_) => crash "fixture clock rejected"
		}
		rules = make_rules(input.first, input.second)
		local = LocalDateTime.new(date, clock)
		# Enumerate the timeline in one-second cells. Offset is a direct
		# piecewise fixture definition, not the production inverse algorithm.
		second = I64.div_floor_by(input.number, 1000000)
		fraction = input.number - second * 1000000
		var expected = []
		var tick = -10.I64
		while tick < 10 {
			offset = if tick < 0 {
				0.I32
			} else if tick < 4 {
				input.first
			} else {
				input.second
			}
			if tick + offset.to_i64() == second {
				expected = expected.append(point(tick * 1000000 + fraction))
			}
			tick = tick + 1
		}
		classification = match expected {
			[] => Gap
			[only] => Unique(only)
			_ => Fold(expected)
		}
		if ZoneRules.resolve(rules, local) != Ok(classification) {
			crash "zone resolution differs from independent timeline enumeration"
		}
		match expected {
			[] => {
				if ZoneRules.resolve_occurrence(rules, local, First) != Err(Gap) {
					crash "gap silently shifted"
				}
			}
			[only] => {
				if ZoneRules.resolve_occurrence(rules, local, RequireUnique) != Ok(only) {
					crash "unique occurrence policy"
				}
			}
			_ => {
				if ZoneRules.resolve_occurrence(rules, local, RequireUnique) != Err(Ambiguous) {
					crash "fold silently chosen"
				}
			}
		}
		for occurrence in expected {
			seconds = I64.div_trunc_by(input.number - PosixBoundary.to_microseconds(occurrence), 1000000).to_i32_wrap()
			snapshot = match ResolvedBoundary.resolve(rules, local, MatchingOffset(FixedOffset.from_seconds(seconds))) {
				Ok(value) => value
				Err(_) => crash "valid snapshot rejected"
			}
			if ResolvedBoundary.boundary(snapshot) != occurrence or ResolvedBoundary.source(snapshot) != local {
				crash "snapshot lost resolution evidence"
			}
			updated = ResolvedBoundary.reresolve(snapshot, make_rules(0, 0))
			if seconds == 0 {
				match updated {
					Ok(value) => if ResolvedBoundary.boundary(value) != point(input.number) {
						crash "snapshot re-resolution wrong"
					}
					Err(_) => crash "valid re-resolution rejected"
				}
			} else {
				match updated {
					Err(OffsetConflict) => {}
					_ => crash "re-resolution discarded offset policy"
				}
			}
			if ZoneRules.resolve_occurrence(rules, local, MatchingOffset(FixedOffset.from_seconds(seconds))) != Ok(occurrence) {
				crash "asserted offset chose wrong occurrence"
			}
		}
		end_number = input.number + 500000
		end_fields = if end_number < 0 {
			{ year: 1969.I64, month: 12.U8, day: 31.U8 }
		} else {
			{ year: 1970.I64, month: 1.U8, day: 1.U8 }
		}
		end_date = match CalendarDate.from_fields(Gregorian, end_fields) {
			Ok(value) => value
			Err(_) => crash "fixture end date rejected"
		}
		end_clock = match ClockTime.from_microseconds_since_midnight(
			if end_number < 0 {
				end_number + 86400000000
			} else {
				end_number
			},
		) {
			Ok(value) => value
			Err(_) => crash "fixture end clock rejected"
		}
		selected = match ZoneRules.select(rules, local, LocalDateTime.new(end_date, end_clock)) {
			Ok(value) => value
			Err(_) => crash "complete local selection rejected"
		}
		snapshot = match ResolvedSelection.resolve(rules, local, LocalDateTime.new(end_date, end_clock)) {
			Ok(value) => value
			Err(_) => crash "complete selection snapshot rejected"
		}
		if ResolvedSelection.coverage(snapshot) != selected {
			crash "selection snapshot changed coverage"
		}
		var probe_second = -10.I64
		while probe_second < 10 {
			for probe_fraction in [0.I64, fraction, 999999] {
				probe = probe_second * 1000000 + probe_fraction
				offset = if probe_second < 0 {
					0.I32
				} else if probe_second < 4 {
					input.first
				} else {
					input.second
				}
				label = probe + offset.to_i64() * 1000000
				expected_member = label >= input.number and label < end_number
				if Coverage.contains(selected, point(probe)) != expected_member {
					crash "local selection differs from direct timeline membership"
				}
			}
			probe_second = probe_second + 1
		}
		Fuzz.keep
	}
}

point = |number| PosixBoundary.from_microseconds(number)

make_span = |lower, upper| match PosixSpan.new(point(lower), point(upper)) {
	Ok(value) => value
	Err(_) => crash "fixture range rejected"
}

make_rules = |first, second| match ZoneRules.new_bounded(
	"Synthetic/Generated",
	"v1",
	make_span(-10000000, 10000000),
	FixedOffset.from_seconds(0),
	[
		{ at: point(0), offset: FixedOffset.from_seconds(first) },
		{ at: point(4000000), offset: FixedOffset.from_seconds(second) },
	],
	{ minimum: -2, maximum: 2 },
) {
	Ok(value) => value
	Err(_) => crash "fixture rules rejected"
}
