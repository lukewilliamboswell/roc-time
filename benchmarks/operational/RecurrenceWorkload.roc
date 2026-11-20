import time.CalendarPattern
import time.DateRecurrence
import time.GregorianDate

## Bounded checks use explicit calendar expectations. The daily window spans a
## leap day with exclusions. The monthly rule skips February and April, which
## have no 31st. The distant window must exhibit bounded incomplete work.
RecurrenceWorkload := [].{
	Mode : [Construct, InvalidCount, First, Window, Resume]
	Outcome : [Definition({ anchor : GregorianDate, exclusions : List(GregorianDate) }), InvalidCount, Dates(List(GregorianDate)), Limited, FirstDate(GregorianDate)]
	Observation : { outcome : Outcome, steps : U64, buffered : U64 }

	prepare = |profile, mode| {
		anchor = match profile {
			"daily" => date(2024, 2, 27)
			"monthly" => date(2000, 1, 31)
			"distant" => date(2000, 1, 1)
			_ => crash "unknown recurrence profile"
		}
		{ pattern, exclusions, start, end, visible, following } = match profile {
			"daily" => {
				pattern: CalendarPattern.defaults(Daily),
				exclusions: [date(2024, 2, 29), date(2024, 3, 2)],
				start: date(2024, 2, 28),
				end: date(2024, 3, 4),
				visible: [date(2024, 2, 28), date(2024, 3, 1), date(2024, 3, 3)],
				following: date(2024, 2, 28),
			}
			"monthly" => {
				pattern: CalendarPattern.defaults(Monthly),
				exclusions: [date(2000, 5, 31)],
				start: date(2000, 3, 1),
				end: date(2000, 6, 1),
				visible: [date(2000, 3, 31)],
				following: date(2000, 3, 31),
			}
			_ => {
				pattern: CalendarPattern.defaults(Daily),
				exclusions: [],
				start: date(1999999999, 12, 25),
				end: date(2000000000, 1, 1),
				visible: [],
				following: date(2000, 1, 2),
			}
		}
		spec = { pattern, exclusions, termination: Forever, by_set_pos: [], inclusions: [] }
		rule = DateRecurrence.new(anchor, spec) ?? crash "checked recurrence fixture"
		window_start = if (mode == Window) start else anchor
		initial = DateRecurrence.cursor(rule, { start: window_start, end }) ?? crash "nonempty fixture window"
		max_steps = if (profile == "distant") 8 else if (profile == "monthly") 256 else 64
		cursor = if mode == Resume {
			prefix = DateRecurrence.Cursor.next(initial, { max_steps, max_buffered: 1 }) ?? crash "fixture prefix"
			match prefix.status {
				Item(item) if item.date == anchor => item.cursor
				_ => crash "fixture prefix changed"
			}
		} else {
			initial
		}
		expected : Outcome
		expected = match mode {
			Construct => Definition({ anchor, exclusions })
			InvalidCount => InvalidCount
			First => FirstDate(anchor)
			Resume => FirstDate(following)
			Window if profile == "distant" => Limited
			Window => Dates(visible)
		}
		{ anchor, spec, cursor, max_steps, expected }
	}

	run : Mode, { anchor : GregorianDate, spec : DateRecurrence.Spec, cursor : DateRecurrence.Cursor, max_steps : U64, expected : Outcome } -> Observation
	run = |mode, fixture| match mode {
		Construct | InvalidCount => {
			spec = if (mode == InvalidCount) { ..fixture.spec, termination: Count(0) } else fixture.spec
			outcome = match DateRecurrence.new(fixture.anchor, spec) {
				Ok(rule) => {
					definition = DateRecurrence.definition(rule)
					Definition({ anchor: definition.anchor, exclusions: definition.spec.exclusions })
				}
				Err(InvalidCount) => InvalidCount
				Err(_) => crash "unexpected recurrence definition error"
			}
			{ outcome, steps: 0, buffered: 0 }
		}
		First | Resume => {
			next = DateRecurrence.Cursor.next(fixture.cursor, { max_steps: fixture.max_steps, max_buffered: 1 }) ?? crash "fixture next"
			outcome = match next.status {
				Item(item) => FirstDate(item.date)
				_ => crash "fixture expected next date"
			}
			{ outcome, steps: next.steps, buffered: next.buffered }
		}
		Window => {
			batch = DateRecurrence.Cursor.collect(fixture.cursor, { max_steps: fixture.max_steps, max_buffered: 4, max_occurrences: 4 }) ?? crash "fixture query"
			outcome = match batch.status {
				Complete => Dates(batch.dates)
				Limited({ reason: WorkLimit, .. }) if batch.dates.is_empty() => Limited
				_ => crash "unexpected recurrence batch status"
			}
			{ outcome, steps: batch.steps, buffered: batch.buffered }
		}
	}

	checksum : Observation -> U64
	checksum = |{ outcome, steps, buffered }| {
		amount = match outcome {
			Definition({ anchor, exclusions }) => exclusions.fold(observe(anchor), |sum, value| sum + observe(value))
			Dates(dates) => dates.fold(1, |sum, value| sum + observe(value))
			FirstDate(value) => observe(value)
			InvalidCount => 2
			Limited => 3
		}
		amount + steps + buffered
	}
}

date = |year, month, day| GregorianDate.from_fields({ year, month, day }) ?? crash "calendar fixture"

observe = |value| {
	fields = GregorianDate.to_fields(value)
	fields.year.to_u64_wrap() * 10000 + fields.month.to_u64() * 100 + fields.day.to_u64()
}
