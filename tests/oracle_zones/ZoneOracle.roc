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

	## The JSONL harness sends validated scalar arguments; the public temporal
	## constructors still validate calendar fields and rule interpretation.
	run_args = |args, fixtures| {
		if args.len() != 11 or argument(args, 2) != "resolve" {
			crash "Invalid zone oracle transport"
		}
		id = argument(args, 1)
		_id_number = match U64.from_str(id) {
			Ok(n) => n
			Err(_) => crash "Invalid case identity"
		}
		result = execute(args, fixtures)
		match result {
			Ok(candidates) => {
				var text = "${id}\tok"
				for candidate in candidates {
					text = "${text}\t${candidate.to_str()}"
				}
				"${text}\n"
			}
			Err(error) => "${id}\terror\t${Str.inspect(error)}\n"
		}
	}

	execute = |args, fixtures| {
		if args.len() != 11 or argument(args, 2) != "resolve" {
			return Err(InvalidArguments)
		}
		index = U64.from_str(argument(args, 3))?
		year = I64.from_str(argument(args, 4))?
		month = U8.from_str(argument(args, 5))?
		day = U8.from_str(argument(args, 6))?
		hour = U8.from_str(argument(args, 7))?
		minute = U8.from_str(argument(args, 8))?
		second = U8.from_str(argument(args, 9))?
		microsecond = U32.from_str(argument(args, 10))?
		fixture = fixtures.get(index)?
		rules = rules_for(fixture)?
		date = CalendarDate.from_fields(Gregorian, { year, month, day })?
		clock = ClockTime.from_fields({ hour, minute, second, microsecond })?
		resolution = ZoneRules.resolve(rules, LocalDateTime.new(date, clock))?
		Ok(
			match resolution {
				Gap => []
				Unique(boundary) => [PosixBoundary.to_microseconds(boundary)]
				Fold(boundaries) => boundaries.map(PosixBoundary.to_microseconds)
			},
		)
	}

	argument = |args, index| match args.get(index) {
		Ok(value) => value
		Err(_) => crash "Missing zone oracle argument"
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
