import time.CalendarValue
import time.CalendarEvidence
import time.IntervalEvidence
import time.QualifiedCalendarValue
import time.CalendarDate
import time.RfcPeriod
import time.RfcDateTime
import time.EdtfDate
import time.OffsetTimestamp
import time.ExactInterval
import time.Ixdtf
import time.RfcDuration
import time.CivilDay
import time.GregorianDate
import time.PosixBoundary
import time.PosixDelta
import time.PosixSpan
import time.Coverage

DispatchChecks :: [].{
	run : {} -> Try({}, [InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidMicrosecond, OutOfRange, InvalidMonth, InvalidDay, EmptySpan, ReversedBounds, Submicrosecond, Failed, ..])
	run = |_| {
		annotated = parse_ixdtf("1970-01-01T00:00:00Z[+00:00][knort=value]")?
		same_annotated = parse_ixdtf("1970-01-01t00:00:00-00:00[-00:00][knort=value]")?
		critical = parse_ixdtf("1970-01-01T00:00:00Z[!+00:00][knort=value]")?
		if annotated != same_annotated or annotated == critical or Dict.get(Dict.insert(Dict.empty(), annotated, 43.U64), same_annotated) != Ok(43) or !Str.inspect(annotated).contains("tags=1") {
			return Err(Failed)
		}
		exact = parse_exact("1970-01-01T00:00:00Z/1970-01-01T01:00:00Z")?
		same_exact = parse_exact("1970-01-01t00:00:00-00:00/1970-01-01t01:00:00z")?
		if exact != same_exact or Dict.get(Dict.insert(Dict.empty(), exact, 41.U64), same_exact) != Ok(41) or !Str.inspect(exact).contains("ExactInterval") {
			return Err(Failed)
		}
		archive = parse_archive("2004-06~")?
		same_archive = parse_archive("2004-06~")?
		if archive != same_archive or Dict.get(Dict.insert(Dict.empty(), archive, 31.U64), same_archive) != Ok(31) or !Str.inspect(archive).contains("2004-06~") {
			return Err(Failed)
		}
		stamp = parse_offset("1970-01-01T00:00:00.120Z")?
		same_stamp = parse_offset("1970-01-01t00:00:00.120-00:00")?
		asserted = parse_offset("1970-01-01T00:00:00.120+00:00")?
		coarser = parse_offset("1970-01-01T00:00:00.12Z")?
		if stamp != same_stamp or stamp == asserted or stamp == coarser or Dict.get(Dict.insert(Dict.empty(), stamp, 37.U64), same_stamp) != Ok(37) or !Str.inspect(stamp).contains(".120Z") {
			return Err(Failed)
		}
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
		description_date = CalendarDate.from_fields(Gregorian, { year: 2024, month: 1, day: 1 })?
		minute_value = CalendarValue.minute(description_date, 12, 30)?
		second_value = CalendarValue.second(description_date, 12, 30, 0)?
		descriptions = Dict.insert(Dict.insert(Dict.empty(), minute_value, 1.U64), second_value, 2.U64)
		if minute_value == second_value or Dict.get(descriptions, minute_value) != Ok(1) or Dict.get(descriptions, second_value) != Ok(2) or !Str.inspect(minute_value).contains("resolution=Minute") {
			return Err(Failed)
		}

		qualified_minute = qualify(minute_value, [{ scope: Minute, qualifier: Approximate }, { scope: Whole, qualifier: Uncertain }])?
		reordered = qualify(minute_value, [{ scope: Whole, qualifier: Uncertain }, { scope: Minute, qualifier: Approximate }])?
		if Dict.get(Dict.insert(Dict.empty(), qualified_minute, 3.U64), reordered) != Ok(3) or !Str.inspect(qualified_minute).contains("Approximate") {
			return Err(Failed)
		}

		evidence = evidence_for(qualified_minute, [minute_value, minute_value])?
		singleton = evidence_for(reordered, [minute_value])?
		if evidence != singleton or Dict.get(Dict.insert(Dict.empty(), evidence, 4.U64), singleton) != Ok(4) or !Str.inspect(evidence).contains("alternatives=1") {
			return Err(Failed)
		}

		interval = interval_model([PosixBoundary.from_microseconds(0), PosixBoundary.from_microseconds(2), PosixBoundary.from_microseconds(0)], [PosixBoundary.from_microseconds(3)])?
		reordered_interval = interval_model([PosixBoundary.from_microseconds(2), PosixBoundary.from_microseconds(0)], [PosixBoundary.from_microseconds(3)])?
		if interval != reordered_interval or Dict.get(Dict.insert(Dict.empty(), interval, 5.U64), reordered_interval) != Ok(5) or Str.inspect(interval) != "IntervalEvidence(Independent, starts=2, ends=1)" {
			return Err(Failed)
		}

		period = parse_period("19970101T180000Z/PT1H")?
		same_period = parse_period("19970101t180000z/+PT60M")?
		if period != same_period or Dict.get(Dict.insert(Dict.empty(), period, 23.U64), same_period) != Ok(23) or Str.inspect(period) != "RfcPeriod(19970101T180000Z/PT3600S)" {
			return Err(Failed)
		}
		utc = parse_datetime("19700101T000000Z")?
		lower = parse_datetime("19700101t000000z")?
		local = parse_datetime("19700101T000000")?
		if utc != lower or utc == local or Dict.get(Dict.insert(Dict.empty(), utc, 19.U64), lower) != Ok(19) or Str.inspect(local) != "RfcDateTime(19700101T000000, Local)" {
			return Err(Failed)
		}
		week = parse_duration("P1W")?
		days = parse_duration("P7D")?
		if week != days or Dict.get(Dict.insert(Dict.empty(), week, 17.U64), days) != Ok(17) or Str.inspect(week) != "RfcDuration(P7D)" {
			return Err(Failed)
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
		var many = []
		var index = 0.I64
		while index < 10000 {
			many = many.append(PosixSpan.new(PosixBoundary.from_microseconds(index * 2), PosixBoundary.from_microseconds(index * 2 + 1))?)
			index = index + 1
		}
		large = Coverage.from_spans(many)
		text = Str.inspect(large)
		if !text.contains("members=10000") or !text.contains("omitted=9996") or
			text.contains("[8, 9)") or !text.contains("[6, 7)") or text.count_utf8_bytes() > 600 {
			return Err(Failed)
		}
		# Debugging must not require a representable accumulated width.
		wide = PosixSpan.new(PosixBoundary.from_microseconds(I64.lowest), PosixBoundary.from_microseconds(I64.highest))?
		if !Str.inspect(Coverage.from_spans([wide])).contains("9223372036854775807") {
			return Err(Failed)
		}
		Ok({})
	}
}

parse_archive = |text| match EdtfDate.parse(text) {
	Ok(value) => Ok(value)
	Err(_) => Err(Failed)
}

parse_exact = |text| match ExactInterval.parse(text) {
	Ok(value) => Ok(value)
	Err(_) => Err(Failed)
}

parse_ixdtf = |text| match Ixdtf.parse(text) {
	Ok(value) => Ok(value)
	Err(_) => Err(Failed)
}

parse_offset = |text| match OffsetTimestamp.parse(text) {
	Ok(value) => Ok(value)
	Err(_) => Err(Failed)
}

parse_duration : Str -> Try(RfcDuration, [Failed, ..])
parse_duration = |text| match RfcDuration.parse(text) {
	Ok(value) => Ok(value)
	Err(_) => Err(Failed)
}

parse_datetime : Str -> Try(RfcDateTime, [Failed, ..])
parse_datetime = |text| match RfcDateTime.parse(text) {
	Ok(value) => Ok(value)
	Err(_) => Err(Failed)
}

parse_period : Str -> Try(RfcPeriod, [Failed, ..])
parse_period = |text| match RfcPeriod.parse(text) {
	Ok(value) => Ok(value)
	Err(_) => Err(Failed)
}

qualify = |value, items| match QualifiedCalendarValue.new(value, items) {
	Ok(found) => Ok(found)
	Err(_) => Err(Failed)
}

evidence_for = |description, values| match CalendarEvidence.new(description, values) {
	Ok(value) => Ok(value)
	Err(_) => Err(Failed)
}

interval_model = |starts, ends| match IntervalEvidence.independent({ starts, ends }) {
	Ok(value) => Ok(value)
	Err(_) => Err(Failed)
}
