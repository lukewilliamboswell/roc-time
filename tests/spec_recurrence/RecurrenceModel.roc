import fuzz.Model
import time.GregorianDate
import time.Recurrence.CalendarPattern as CalendarPattern
import time.Recurrence.Date as DateRecurrence
import time.Recurrence.DateCursor as DateCursor

# R11–R12. A booking reader changes budgets and consumption APIs mid-query,
# keeping the cursor from the first call to read both branches independently.
# January 2025 needs no calendar oracle: interval 2 and COUNT 3 give days
# 1, 3, 5. The exclusions remove 3 even when explicitly included; additions
# 2 and 6 survive, and day 8 sits on the exclusive end of both windows.
RecurrenceModel :: [].{
	Reader : [OneStep, NoOutput, NoBuffer, Next, FoldStop]
	Action : [OpenEarly, OpenLate, Read(Reader), Finish]
	Status : [Ready, Limited(DateRecurrence.Limit), Item, Stopped, Complete, Error]
	Batch : { cursor : [None, Some(DateCursor)], days : List(U8), steps : U64, buffered : U64, occurrences : U64, status : Status }
	Branch : { batch : Batch, remaining : List(U8) }
	World : { history : List(Action), current : Branch, saved : Branch, finished : Bool, recovered : Bool }

	date : U8 -> GregorianDate
	date = |day| GregorianDate.from_fields({ year: 2025, month: 1, day }) ?? crash "invalid fixture date"

	open : U8 -> Branch
	open = |start| {
		rule = DateRecurrence.new(
			date(1),
			{
				pattern: { ..CalendarPattern.defaults(Daily), interval: 2 },
				termination: Count(3),
				by_set_pos: [],
				inclusions: [date(6), date(2), date(3), date(6), date(8)],
				exclusions: [date(3)],
			},
		) ?? crash "invalid fixture rule"
		cursor = DateRecurrence.cursor(rule, { start: date(start), end: date(8) }) ?? crash "invalid fixture window"
		{ batch: { ..empty.batch, cursor: Some(cursor) }, remaining: [2, 5, 6].keep_if(|day| day >= start) }
	}

	empty : Branch
	empty = {
		batch: { cursor: None, days: [], steps: 0, buffered: 0, occurrences: 0, status: Ready },
		remaining: [],
	}

	generous : DateRecurrence.Limits
	generous = { max_steps: 256, max_buffered: 1, max_occurrences: 8 }

	limits_for : Reader -> DateRecurrence.Limits
	limits_for = |reader| match reader {
		OneStep => { ..generous, max_steps: 1 }
		NoOutput => { ..generous, max_occurrences: 0 }
		NoBuffer => { ..generous, max_buffered: 0 }
		Next | FoldStop => { ..generous, max_occurrences: 1 }
	}

	fields_day : GregorianDate -> U8
	fields_day = |value| {
		fields = GregorianDate.to_fields(value)
		if fields.year == 2025 and fields.month == 1 {
			fields.day
		} else {
			0
		}
	}

	collect : DateCursor, DateRecurrence.Limits -> Batch
	collect = |cursor, limits| match DateCursor.collect(cursor, limits) {
		Err(_) => { ..empty.batch, status: Error }
		Ok(batch) => {
			(remaining, status) = match batch.status {
				Complete => (None, Complete)
				Limited(progress) => (Some(progress.cursor), Limited(progress.reason))
			}
			{ cursor: remaining, status, days: batch.dates.map(fields_day), steps: batch.steps, buffered: batch.buffered, occurrences: batch.dates.len() }
		}
	}

	read : DateCursor, Reader -> Batch
	read = |cursor, reader| {
		limits = limits_for(reader)
		match reader {
			Next => match DateCursor.next(cursor, { max_steps: limits.max_steps, max_buffered: limits.max_buffered }) {
				Err(_) => { ..empty.batch, status: Error }
				Ok(next) => {
					batch = { ..empty.batch, steps: next.steps, buffered: next.buffered }
					match next.status {
						End => { ..batch, status: Complete }
						Item(item) => { ..batch, cursor: Some(item.cursor), status: Item, days: [fields_day(item.date)], occurrences: 1 }
						Limited(progress) => { ..batch, cursor: Some(progress.cursor), status: Limited(progress.reason) }
					}
				}
			}
			FoldStop => match DateCursor.fold(cursor, { limits, initial: [], visit: |days, value| Stop(days.append(fields_day(value))) }) {
				Err(_) => { ..empty.batch, status: Error }
				Ok(batch) => {
					(remaining, status) = match batch.status {
						Complete => (None, Complete)
						Stopped(rest) => (Some(rest), Stopped)
						Limited(progress) => (Some(progress.cursor), Limited(progress.reason))
					}
					{ cursor: remaining, status, days: batch.value, steps: batch.steps, buffered: batch.buffered, occurrences: batch.occurrences }
				}
			}
			_ => collect(cursor, limits)
		}
	}

	# A generous drain is checked against the independent suffix, including
	# the branch still held from the first read. A complete transport call
	# can have occurred before Finish, so it must have no expected dates left.
	resumes : Branch -> Bool
	resumes = |branch| match branch.batch.cursor {
		None => branch.batch.status == Complete and branch.remaining.is_empty()
		Some(cursor) => {
			batch = collect(cursor, generous)
			batch.status == Complete and batch.days == branch.remaining
		}
	}

	actions : World -> List(Action)
	actions = |world| {
		if world.history.is_empty() {
			return [OpenEarly, OpenLate]
		}
		if world.finished {
			return []
		}
		match world.current.batch.cursor {
			Some(_) => if world.history.len() <= 3 {
				readers = [Read(OneStep), Read(NoOutput), Read(NoBuffer), Read(Next), Read(FoldStop)]
				if world.history.len() == 1 {
					readers
				} else {
					readers.append(Finish)
				}
			} else {
				[Finish]
			}
			None => [Finish]
		}
	}

	step : World, Action -> World
	step = |world, action| {
		advanced = { ..world, history: world.history.append(action) }
		match action {
			OpenEarly => { ..advanced, current: open(2) }
			OpenLate => { ..advanced, current: open(5) }
			Read(reader) => {
				cursor = match world.current.batch.cursor {
					Some(value) => value
					None => crash "read outside live branch"
				}
				batch = read(cursor, reader)
				current = { batch, remaining: world.current.remaining.drop_first(batch.days.len()) }
				saved = if world.history.len() == 1 {
					current
				} else {
					world.saved
				}
				{ ..advanced, current, saved }
			}
			Finish => { ..advanced, finished: True, recovered: resumes(world.current) and resumes(world.saved) }
		}
	}

	valid_read : Branch, Reader, Batch -> Bool
	valid_read = |before, reader, after| {
		limits = limits_for(reader)
		prefix = before.remaining.take_first(after.days.len())
		if after.days != prefix or after.steps > limits.max_steps or
			after.occurrences > limits.max_occurrences or after.occurrences != after.days.len() {
			return False
		}
		# On a capacity decrease the old buffer stays intact and costs no work.
		if before.batch.buffered > limits.max_buffered {
			return after.status == Limited(BufferLimit) and after.steps == 0 and after.days.is_empty() and after.buffered == before.batch.buffered
		}
		if after.buffered > limits.max_buffered {
			return False
		}
		match after.status {
			Complete => after.days == before.remaining
			Limited(WorkLimit) => after.steps == limits.max_steps
			Limited(OutputLimit) => after.occurrences == limits.max_occurrences and after.days.len() < before.remaining.len()
			Limited(BufferLimit) => after.buffered == limits.max_buffered
			Item => reader == Next and after.days.len() == 1
			Stopped => reader == FoldStop and after.days.len() == 1
			_ => False
		}
	}

	machine : Model.Machine(World, Action)
	machine = {
		init: { history: [], current: empty, saved: empty, finished: False, recovered: False },
		actions,
		step,
		rules: [
			Model.always_step(
				"each read emits the next prefix and respects work, buffer and output budgets",
				|{ before, action, after }| match action {
					Read(reader) => valid_read(before.current, reader, after.current.batch)
					_ => True
				},
			),
			Model.at_rest("both continuations recover the exact remaining dates", |world| world.finished and world.recovered),
			Model.sometimes_step("one step yields a work limit", |{ action, after, before: _ }| action == Read(OneStep) and after.current.batch.status == Limited(WorkLimit)),
			Model.sometimes_step("withheld output leaves a buffered candidate", |{ action, after, before: _ }| action == Read(NoOutput) and after.current.batch.status == Limited(OutputLimit) and after.current.batch.buffered > 0),
			Model.sometimes_step("shrinking a live buffer yields without work", |{ before, action, after }| action == Read(NoBuffer) and before.current.batch.buffered > 0 and after.current.batch.status == Limited(BufferLimit) and after.current.batch.steps == 0),
			Model.sometimes_step("next consumes a date", |{ action, after, before: _ }| action == Read(Next) and after.current.batch.status == Item),
			Model.sometimes_step("a visitor stops on a date", |{ action, after, before: _ }| action == Read(FoldStop) and after.current.batch.status == Stopped),
			Model.sometimes_step("the retained continuation recovers a longer suffix", |{ before, action, after }| action == Finish and after.recovered and before.saved.remaining.len() > before.current.remaining.len()),
		],
	}

	# The opaque cursor may have work or pending dates even when its remaining
	# output is unchanged. Use the complete bounded history as the search key.
	# The model allows up to three reads after opening either window. A shrink
	# that advances the explicit-date stream drops Jan 2 on the history
	# [OpenEarly, Read(NoOutput), Read(NoBuffer), Read(Next)].
	expect {
		report = Model.explore(machine, { depth: 6, key: |world| world.history, verify: EveryStep, blame: EveryRule })
		if report.verdict != Holds(Exhausted) {
			dbg report
		}
		report.verdict == Holds(Exhausted)
	}

}
