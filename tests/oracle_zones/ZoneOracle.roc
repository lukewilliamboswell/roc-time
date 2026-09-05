import time.CalendarDate
import time.ClockTime
import time.FixedOffset
import time.LocalDateTime
import time.PosixBoundary
import time.PosixSpan
import time.ZoneRules

ZoneOracle :: [].{
	Fixture : { name : Str, lower : I64, upper : I64, initial : I32, minimum : I32, maximum : I32, transitions : List({ at : I64, offset : I32 }) }
	Case : { id : U64, zone : U64, date : CalendarDate.Fields, clock : ClockTime.Fields, expected : List(I64) }

	rules_for = |fixture| {
		validity = PosixSpan.new(PosixBoundary.from_microseconds(fixture.lower), PosixBoundary.from_microseconds(fixture.upper))?
		var transitions = []
		for transition in fixture.transitions {
			transitions = transitions.append({ at: PosixBoundary.from_microseconds(transition.at), offset: FixedOffset.from_seconds(transition.offset) })
		}
		ZoneRules.new_bounded(fixture.name, "IANA-2025b", validity, FixedOffset.from_seconds(fixture.initial), transitions, { minimum: fixture.minimum, maximum: fixture.maximum })
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
		fixture = { name: "Synthetic/Comparator", lower: -1000000, upper: 1000000, initial: 0, minimum: 0, maximum: 0, transitions: [] }
		good : Case
		good = { id: 0, zone: 0, date: { year: 1970, month: 1, day: 1 }, clock: { hour: 0, minute: 0, second: 0, microsecond: 0 }, expected: [0] }
		wrong = { ..good, expected: [1] }
		verify([fixture], [good], 1) == Ok(1) and
			verify([fixture], [wrong], 1) == Err(Mismatch(0)) and
				verify([fixture], [], 1) == Err(CaseCount) and
					verify([fixture], [good, good], 2) == Err(CaseOrder(0))
	}
}
