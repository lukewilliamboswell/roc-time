import time.CalendarDate
import time.ClockTime
import time.LocalDateTime
import time.PosixBoundary
import time.ZoneRules

ZoneOracle :: [].{
	Fixture : { name : Str, source_digest : Str, lower : I64, upper : I64, initial : I32, minimum : I32, maximum : I32, transitions : List({ at : I64, offset : I32 }) }
	Case : { id : U64, zone : U64, date : CalendarDate.Fields, clock : ClockTime.Fields, expected : List(I64) }

	rules_for = |fixture| {
		if I64.rem_by(fixture.lower, 1000000) != 0 or I64.rem_by(fixture.upper, 1000000) != 0 {
			return Err(FixturePrecision)
		}
		var transitions = []
		for transition in fixture.transitions {
			if I64.rem_by(transition.at, 1000000) != 0 {
				return Err(FixturePrecision)
			}
			transitions = transitions.append({ second: I64.div_trunc_by(transition.at, 1000000), offset: transition.offset })
		}
		ZoneRules.from_database({
			schema: 1,
			axis: "posix-seconds-1970",
			requested_name: fixture.name,
			canonical_name: fixture.name,
			source_version: "IANA-2025b",
			source_digest: fixture.source_digest,
			profile: "tzdata-2025.2-selected-windows",
			future_handling: "expanded-through-validity",
			start_second: I64.div_trunc_by(fixture.lower, 1000000),
			end_second: I64.div_trunc_by(fixture.upper, 1000000),
			initial_offset: fixture.initial,
			minimum_offset: fixture.minimum,
			maximum_offset: fixture.maximum,
			transitions,
		})
	}

	verify = |fixtures, cases, count| {
		if List.len(cases) != count {
			return Err(CaseCount)
		}
		var rules = []
		for fixture in fixtures {
			rules = rules.append(rules_for(fixture)?)
		}
		var visited = 0.U64
		for case in cases {
			if case.id != visited {
				return Err(CaseOrder(case.id))
			}
			zone = List.get(rules, case.zone)?
			date = CalendarDate.from_fields(Gregorian, case.date)?
			clock = ClockTime.from_fields(case.clock)?
			result = ZoneRules.resolve(zone, LocalDateTime.new(date, clock))?
			actual = match result {
				Gap => []
				Unique(boundary) => [PosixBoundary.to_microseconds(boundary)]
				Fold(boundaries) => boundaries.map(PosixBoundary.to_microseconds)
			}
			if actual != case.expected {
				return Err(Mismatch(case.id))
			}
			visited = visited + 1
		}
		Ok(visited)
	}

	expect {
		fixture : Fixture
		fixture = { name: "Synthetic/Comparator", source_digest: "fixture-v1", lower: -1000000, upper: 1000000, initial: 0, minimum: 0, maximum: 0, transitions: [] }
		good : Case
		good = { id: 0, zone: 0, date: { year: 1970, month: 1, day: 1 }, clock: { hour: 0, minute: 0, second: 0, microsecond: 0 }, expected: [0] }
		wrong = { ..good, expected: [1] }
		verify([fixture], [good], 1) == Ok(1) and
			verify([fixture], [wrong], 1) == Err(Mismatch(0)) and
				verify([fixture], [], 1) == Err(CaseCount) and
					verify([fixture], [good, good], 2) == Err(CaseOrder(0))
	}
}
