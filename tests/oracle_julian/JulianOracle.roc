import time.CivilDay
import time.JulianDate

## Public inputs and typed observations; generated expectations never call roc-time.
JulianOracle := [Forward(I64, U8, U8), Inverse(I64)].{
	Observation : [DayNumber(I64), DateFields(I64, U8, U8), Failure([OutOfRange, InvalidMonth, InvalidDay])]
	Case : { id : U64, input : JulianOracle, expected : Observation }

	observe : JulianOracle -> Observation
	observe = |input| {
		match input {
			Forward(year, month, day) => {
				match JulianDate.from_fields({ year, month, day }) {
					Ok(date) => DayNumber(CivilDay.to_day_number(JulianDate.to_civil_day(date)))
					Err(error) => Failure(error)
				}
			}
			Inverse(number) => {
				match JulianDate.from_civil_day(CivilDay.from_day_number(number)) {
					Ok(date) => {
						f = JulianDate.to_fields(date)
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
		first = { id: 0, input: Forward(1969, 12, 19), expected: DayNumber(0) }
		wrong : Case
		wrong = { id: 0, input: Forward(1969, 12, 19), expected: DayNumber(1) }
		leap : Case
		leap = { id: 0, input: Inverse(11029), expected: DateFields(2000, 2, 28) }
		verify([first], 1) == Ok(1) and verify([wrong], 1) == Err(Mismatch(0)) and
			verify([leap], 1) == Err(Mismatch(0)) and verify([], 1) == Err(CaseCount) and
				verify([first, first], 2) == Err(CaseOrder(0))
	}
	expect self_check({})

}
