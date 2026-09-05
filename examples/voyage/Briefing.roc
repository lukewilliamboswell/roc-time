import time.ResolvedBoundary
import time.ZoneRules
import time.FixedOffset
import time.LocalDateTime
import time.CalendarDate
import time.ClockTime

## Compare a saved booking with an explicit interpretation of a revised itinerary.
Briefing :: { saved : ResolvedBoundary, revised : ResolvedBoundary }.{
	book = |rules, local| ResolvedBoundary.resolve(rules, local, RequireUnique)

	review = |saved, new_rules| {
		revised = ResolvedBoundary.reresolve(saved, new_rules)?
		Ok({ saved, revised })
	}

	report = |reviewed| {
		old_time = utc_label(reviewed.saved)?
		new_time = utc_label(reviewed.revised)?
		old_version = ZoneRules.version(ResolvedBoundary.rules(reviewed.saved))
		new_version = ZoneRules.version(ResolvedBoundary.rules(reviewed.revised))
		Ok("Research voyage: briefing on 2026-07-01 at 12:00 ship time\nSaved booking (${old_version}): ${old_time} UTC\nRevised itinerary (${new_version}): ${new_time} UTC\nThe saved booking remains unchanged; adopting the revised time is an application decision.\n")
	}
}

utc_label = |snapshot| {
	local = FixedOffset.project(FixedOffset.from_seconds(0), ResolvedBoundary.boundary(snapshot), Gregorian)?
	date = CalendarDate.to_fields(LocalDateTime.date(local))
	clock = ClockTime.to_fields(LocalDateTime.clock(local))
	Ok("${date.year.to_str()}-${pad(date.month)}-${pad(date.day)} ${pad(clock.hour)}:${pad(clock.minute)}")
}

# These briefing times are minute-aligned; this is application presentation.
pad = |number| if number < 10 {
	"0${number.to_str()}"
} else {
	number.to_str()
}
