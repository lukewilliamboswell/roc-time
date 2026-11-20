import zones.Database
import time.EnglishGregorian
import time.FixedOffset
import time.LocalDateTime
import time.PosixBoundary
import time.PosixDelta
import time.ZoneRules

## Keep a local appointment's clock label while advancing one civil day.
## Each caller chooses a source occurrence and a target display zone explicitly.
ZonedAppointment :: [].{
	rules = |name| ZoneRules.from_database(Database.get(name)?)

	parse = |text| match LocalDateTime.parse_gregorian(text) {
		Ok(value) => Ok(value)
		Err(error) => Err(Input(error))
	}

	next_day = |local| local.add_days(1)

	resolve = |zone, local, policy| ZoneRules.resolve_occurrence(zone, { local, occurrence: policy })
	classify = |zone, local| ZoneRules.resolve(zone, local)

	project = |zone, boundary| {
		{ offset, local } = ZoneRules.project(zone, { boundary, calendar: Gregorian })?
		text = match EnglishGregorian.local_datetime(local, Exact) {
			Ok(value) => value
			Err(error) => return Err(Presentation(error))
		}
		Ok({ local, offset_seconds: FixedOffset.to_seconds(offset), text })
	}

	compare_days = |source, target, text, policy| {
		first_local = parse(text)?
		next_local = next_day(first_local)?
		first = resolve(source, first_local, policy)?
		next = resolve(source, next_local, policy)?
		first_display = project(target, first)?.text
		next_display = project(target, next)?.text
		width = PosixBoundary.difference({ left: next, right: first })?
		Ok({ first, next, first_local, next_local, first_display, next_display, coordinate_microseconds: PosixDelta.to_microseconds(width) })
	}
}
