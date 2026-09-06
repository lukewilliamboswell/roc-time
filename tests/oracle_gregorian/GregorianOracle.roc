import time.RfcDateTime
import time.PosixBoundary
import time.CivilDay
import time.GregorianDate

## Public inputs and typed observations; generated expectations never call roc-time.
GregorianOracle := [Forward(I64, U8, U8), Inverse(I64)].{
	Observation : [DayNumber(I64), DateFields(I64, U8, U8), Failure([OutOfRange, InvalidMonth, InvalidDay])]
	Case : { id : U64, input : GregorianOracle, expected : Observation }

	observe : GregorianOracle -> Observation
	observe = |input| {
		match input {
			Forward(year, month, day) => {
				match GregorianDate.from_fields({ year, month, day }) {
					Ok(date) => {
						number = CivilDay.to_day_number(GregorianDate.to_civil_day(date))
						# Replay the independently generated Gregorian expectations
						# through the text adapter on its 0001..9999 intersection.
						if year >= 1 and year <= 9999 {
							y = year.to_str()
							m = month.to_str()
							d = day.to_str()
							text = "${"0".repeat(4 - y.count_utf8_bytes())}${y}${"0".repeat(2 - m.count_utf8_bytes())}${m}${"0".repeat(2 - d.count_utf8_bytes())}${d}T000000Z"
							parsed = match RfcDateTime.parse(text) {
								Ok(value) => value
								Err(_) => crash "oracle date rejected by RFC adapter"
							}
							boundary = match RfcDateTime.utc_boundary(parsed) {
								Ok(value) => value
								Err(_) => crash "oracle UTC value failed to resolve"
							}
							if PosixBoundary.to_microseconds(boundary) != number * 86400000000 {
								crash "RFC midnight differs from civil-day coordinate"
							}
						}
						DayNumber(number)
					}
					Err(error) => Failure(error)
				}
			}
			Inverse(number) => {
				match GregorianDate.from_civil_day(CivilDay.from_day_number(number)) {
					Ok(date) => {
						f = GregorianDate.to_fields(date)
						DateFields(f.year, f.month, f.day)
					}
					Err(error) => Failure(error)
				}
			}
		}
	}

	verify : List(Case), U64 -> Try(U64, [CaseOrder(U64), Mismatch(U64), CaseCount, ..])
	verify = |cases, count| {
		if List.len(cases) != count {
			return Err(CaseCount)
		}
		var visited = 0.U64
		for case in cases {
			if case.id != visited {
				return Err(CaseOrder(case.id))
			}
			if observe(case.input) != case.expected {
				return Err(Mismatch(case.id))
			}
			visited = visited + 1
		}
		Ok(visited)
	}

	## Exercise the actual comparator with wrong epoch/leap-day expectations,
	## dropped cases, and repeated identities before accepting a corpus run.
	self_check : {} -> Bool
	self_check = |_| {
		first : Case
		first = { id: 0, input: Forward(1970, 1, 1), expected: DayNumber(0) }
		wrong : Case
		wrong = { id: 0, input: Forward(1970, 1, 1), expected: DayNumber(1) }
		leap : Case
		leap = { id: 0, input: Inverse(11016), expected: DateFields(2000, 2, 28) }
		verify([first], 1) == Ok(1) and verify([wrong], 1) == Err(Mismatch(0)) and
			verify([leap], 1) == Err(Mismatch(0)) and verify([], 1) == Err(CaseCount) and
				verify([first, first], 2) == Err(CaseOrder(0))
	}
	expect self_check({})

	## Harness argv is validated independently of temporal constructor failures.
	run_args : List(Str) -> Str
	run_args = |args| {
		id = argument(args, 1)
		_validated_id = match U64.from_str(id) {
			Ok(n) => n
			Err(_) => crash "Invalid oracle case id"
		}
		operation = argument(args, 2)
		input = match operation {
			"forward" => {
				if args.len() != 6 {
					crash "Invalid forward argument count"
				}
				year = match I64.from_str(argument(args, 3)) {
					Ok(n) => n
					Err(_) => crash "Invalid year"
				}
				month = match U8.from_str(argument(args, 4)) {
					Ok(n) => n
					Err(_) => crash "Invalid month input"
				}
				day = match U8.from_str(argument(args, 5)) {
					Ok(n) => n
					Err(_) => crash "Invalid day input"
				}
				Forward(year, month, day)
			}
			"inverse" => {
				if args.len() != 4 {
					crash "Invalid inverse argument count"
				}
				number = match I64.from_str(argument(args, 3)) {
					Ok(n) => n
					Err(_) => crash "Invalid day number"
				}
				Inverse(number)
			}
			_ => crash "Unsupported oracle operation"
		}
		observation = match observe(input) {
			DayNumber(n) => "ok\t${n.to_str()}"
			DateFields(y, m, d) => "ok\t${y.to_str()}\t${m.to_str()}\t${d.to_str()}"
			Failure(error) => {
				label = match error {
					OutOfRange => "OutOfRange"
					InvalidMonth => "InvalidMonth"
					InvalidDay => "InvalidDay"
				}
				"error\t${label}"
			}
		}
		"${id}\t${observation}\n"
	}

	argument : List(Str), U64 -> Str
	argument = |args, index| match args.get(index) {
		Ok(value) => value
		Err(_) => crash "Missing oracle argument"
	}

}
