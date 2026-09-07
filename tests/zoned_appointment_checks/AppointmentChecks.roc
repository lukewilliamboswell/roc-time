import zones.Database
import time.ZoneRules
import time.LocalDateTime
import time.CalendarDate
import time.CalendarArithmetic
import time.CalendarDelta
import time.PosixBoundary
import time.PosixDelta
import time.PosixSpan
import time.FixedOffset

## R01/R05/R07/R09/R16: fixed independent TZif/CPython expectations.
## See provenance.md. Checks use crashes so optimized execution cannot remove
## failed assertions. Expected UTC coordinates are not inputs to the resolver.
AppointmentChecks :: [].{
	run = |missing_zone| {
		paris = ZoneRules.from_database(Database.get("Europe/Paris")?)?
		new_york = ZoneRules.from_database(Database.get("America/New_York")?)?
		for fixture in [
			{ text: "2026-03-28T09:30", next: "2026-03-29T09:30:00", first: 1774686600000000.I64, second: 1774769400000000.I64, width: 82800000000.I64, ny_first: "2026-03-28T04:30:00", ny_second: "2026-03-29T03:30:00" },
			{ text: "2026-10-24T09:30", next: "2026-10-25T09:30:00", first: 1792827000000000, second: 1792917000000000, width: 90000000000, ny_first: "2026-10-24T03:30:00", ny_second: "2026-10-25T04:30:00" },
		] {
			local = parse_fixture(fixture.text)
			date = CalendarDate.as_gregorian(LocalDateTime.date(local))?
			next_date = CalendarArithmetic.shift_day(date, CalendarDelta.days(1), Reject)?
			next = LocalDateTime.new(CalendarDate.from_gregorian(next_date), LocalDateTime.clock(local))
			if LocalDateTime.to_gregorian_text(next) != Ok(fixture.next) {
				crash "calendar day drift"
			}
			first = ZoneRules.resolve_occurrence(paris, local, RequireUnique)?
			second = ZoneRules.resolve_occurrence(paris, next, RequireUnique)?
			if PosixBoundary.to_microseconds(first) != fixture.first or PosixBoundary.to_microseconds(second) != fixture.second {
				crash "source zone coordinate oracle"
			}
			if PosixDelta.to_microseconds(PosixBoundary.difference(second, first)?) != fixture.width {
				crash "calendar day coordinate width"
			}
			check_projection(new_york, first, fixture.ny_first)?
			check_projection(new_york, second, fixture.ny_second)?
		}
		fold = parse_fixture("2026-10-25T02:30")
		first = PosixBoundary.from_microseconds(1792888200000000)
		last = PosixBoundary.from_microseconds(1792891800000000)
		if ZoneRules.resolve(paris, fold) != Ok(Fold([first, last])) {
			crash "fold alternatives oracle"
		}
		if ZoneRules.resolve_occurrence(paris, fold, RequireUnique) != Err(Ambiguous) or ZoneRules.resolve_occurrence(paris, fold, First) != Ok(first) or ZoneRules.resolve_occurrence(paris, fold, Last) != Ok(last) {
			crash "explicit fold policy"
		}
		if ZoneRules.resolve_occurrence(paris, fold, MatchingOffset(FixedOffset.from_seconds(7200))) != Ok(first) or ZoneRules.resolve_occurrence(paris, fold, MatchingOffset(FixedOffset.from_seconds(3600))) != Ok(last) {
			crash "fold offset choice"
		}
		check_projection(new_york, first, "2026-10-24T20:30:00")?
		check_projection(new_york, last, "2026-10-24T21:30:00")?
		gap = parse_fixture("2026-03-29T02:30")
		if ZoneRules.resolve(paris, gap) != Ok(Gap) or ZoneRules.resolve_occurrence(paris, gap, First) != Err(Gap) {
			crash "gap is not an occurrence"
		}
		if Database.get(missing_zone) != Err(UnknownZone(missing_zone)) {
			crash "unknown zone was substituted"
		}
		if ZoneRules.offset_at(paris, PosixSpan.end(ZoneRules.validity(paris))) != Err(OutsideValidity) {
			crash "exclusive rule horizon"
		}
		far_future = parse_fixture("2500-01-01T09:30")
		if ZoneRules.resolve_occurrence(paris, far_future, RequireUnique) != Err(OutsideValidity) {
			crash "outside horizon is not gap"
		}
		Ok({})
	}
}

parse_fixture = |text| match LocalDateTime.parse_gregorian(text) {
	Ok(value) => value
	Err(_) => crash "valid fixture label rejected"
}

check_projection = |rules, boundary, expected| {
	{ local, offset } = ZoneRules.project(rules, boundary, Gregorian)?
	if FixedOffset.to_seconds(offset) != -14400 {
		crash "target offset oracle"
	}
	if LocalDateTime.to_gregorian_text(local) != Ok(expected) {
		crash "target local fields oracle"
	}
	if ZoneRules.resolve_occurrence(rules, local, MatchingOffset(offset)) != Ok(boundary) {
		crash "projection changed boundary"
	}
	Ok({})
}
