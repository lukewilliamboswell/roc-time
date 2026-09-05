import time.CivilDay
import time.GregorianDate
import time.PosixBoundary
import time.PosixDelta
import time.PosixSpan
import time.Coverage

DispatchChecks :: [].{
	run : {} -> Try({}, [OutOfRange, InvalidMonth, InvalidDay, EmptySpan, ReversedBounds, Submicrosecond, Failed, ..])
	run = |_| {
		for a in [I64.lowest, -1.I64, 0, 1, I64.highest] {
			for b in [I64.lowest, -1.I64, 0, 1, I64.highest] {
				left = CivilDay.from_day_number(a)
				right = CivilDay.from_day_number(b)
				point = PosixBoundary.from_microseconds(a)
				other = PosixBoundary.from_microseconds(b)
				delta = PosixDelta.from_microseconds(a)
				other_delta = PosixDelta.from_microseconds(b)
				if (left < right) != (a < b) or (left <= right) != (a <= b) or
					(left > right) != (a > b) or (left >= right) != (a >= b) or
						(point < other) != (a < b) or (point <= other) != (a <= b) or
							(point > other) != (a > b) or (point >= other) != (a >= b) or
								(delta < other_delta) != (a < b) or (delta <= other_delta) != (a <= b) or
									(delta > other_delta) != (a > b) or (delta >= other_delta) != (a >= b) {
					return Err(Failed)
				}
			}
			if Dict.get(Dict.insert(Dict.empty(), CivilDay.from_day_number(a), 7.U64), CivilDay.from_day_number(a)) != Ok(7) or
				Dict.get(Dict.insert(Dict.empty(), PosixBoundary.from_microseconds(a), 7.U64), PosixBoundary.from_microseconds(a)) != Ok(7) or
					Dict.get(Dict.insert(Dict.empty(), PosixDelta.from_microseconds(a), 7.U64), PosixDelta.from_microseconds(a)) != Ok(7) {
				return Err(Failed)
			}
		}
		first = GregorianDate.from_fields({ year: -1, month: 12, day: 31 })?
		next = GregorianDate.from_fields({ year: 0, month: 1, day: 1 })?
		if !(first < next and first <= next and next > first and next >= first) {
			return Err(Failed)
		}
		if Dict.get(Dict.insert(Dict.empty(), first, 9.U64), GregorianDate.from_fields({ year: -1, month: 12, day: 31 })?) != Ok(9) {
			return Err(Failed)
		}
		a = PosixSpan.from_seconds(0.Dec, 1.Dec, RejectSubmicrosecond)?
		b = PosixSpan.from_seconds(1.Dec, 2.Dec, RejectSubmicrosecond)?
		whole = PosixSpan.from_seconds(0.Dec, 2.Dec, RejectSubmicrosecond)?
		coverage = Coverage.from_spans([a, b])
		same = Coverage.from_spans([whole])
		if Dict.get(Dict.insert(Dict.empty(), coverage, 11.U64), same) != Ok(11) or
			Dict.get(Dict.insert(Dict.empty(), whole, 13.U64), PosixSpan.hull(a, b)) != Ok(13) {
			return Err(Failed)
		}
		var members = []
		for span in coverage {
			members = members.append(span)
		}
		if members != [whole] {
			return Err(Failed)
		}
		var empty_count = 0.U64
		for _span in Coverage.empty {
			empty_count = empty_count + 1
		}
		if empty_count != 0 {
			return Err(Failed)
		}
		if Str.inspect(CivilDay.from_day_number(0)) != "CivilDay(0)" or
			Str.inspect(next) != "GregorianDate(0, 1, 1)" {
			return Err(Failed)
		}
		Ok({})
	}
}
