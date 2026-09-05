import CalendarPattern
import CivilDay
import GregorianDate

## Gregorian date-only series. Dates identify occurrences within this series;
## applications pair them with their own series ID. They are not POSIX instants.
## Native CalendarPattern defaults apply; this is not an RFC text adapter.
DateRecurrence :: {
	anchor : GregorianDate,
	pattern : CalendarPattern,
	termination : Termination,
	positions : List(I16),
	inclusions : List(GregorianDate),
	exclusions : List(GregorianDate),
}.{
	Termination : [Forever, Count(U64), Until(GregorianDate)]
	Spec : {
		pattern : CalendarPattern.Spec,
		termination : Termination,
		by_set_pos : List(I16),
		inclusions : List(GregorianDate),
		exclusions : List(GregorianDate),
	}
	Window : { start : GregorianDate, end : GregorianDate }
	Limits : { max_steps : U64, max_buffered : U64, max_occurrences : U64 }
	Limit : [WorkLimit, BufferLimit, OutputLimit]
	Batch : {
		dates : List(GregorianDate),
		steps : U64,
		buffered : U64,
		status : [Complete, Limited({ cursor : Cursor, reason : Limit })],
	}
	FoldBatch(acc) : {
		value : acc,
		occurrences : U64,
		steps : U64,
		buffered : U64,
		status : [Complete, Limited({ cursor : Cursor, reason : Limit }), Stopped(Cursor)],
	}
	Next : {
		steps : U64,
		buffered : U64,
		status : [End, Item({ date : GregorianDate, cursor : Cursor }), Limited({ cursor : Cursor, reason : Limit })],
	}

	## O(366*s + n log n) construction, where s is selector count and n is the
	## number of explicit dates. Each supplied list is limited to 4096 entries.
	## Validate DTSTART against the whole first period, including BYSETPOS.
	## Invalid generated dates are skipped; UNTIL is inclusive. COUNT applies
	## before exclusions; explicit inclusions do not consume or replenish COUNT.
	new : GregorianDate, Spec -> Try(DateRecurrence, [InvalidInterval, TooManySelectors, InvalidSelector(Str), InvalidCombination(Str), InvalidCount, InvalidUntil, UnsynchronizedStart, OutOfRange, ..])
	new = |anchor, spec| {
		if spec.by_set_pos.len() > 4096 or spec.inclusions.len() > 4096 or spec.exclusions.len() > 4096 {
			return Err(TooManySelectors)
		}
		for position in spec.by_set_pos {
			if position == 0 or position < -366 or position > 366 {
				return Err(InvalidSelector("BYSETPOS"))
			}
		}
		match spec.termination {
			Count(0) => return Err(InvalidCount)
			Until(end) => if end < anchor {
				return Err(InvalidUntil)
			}
			_ => {}
		}
		pattern = CalendarPattern.new(anchor, spec.pattern)?
		frame = CalendarPattern.period(pattern, 0)?
		var day = number(frame.start)
		var count = 0.U64
		var anchor_position = None
		while day < number(frame.end) {
			date = from_number(day)?
			if CalendarPattern.matches(pattern, 0, date)? {
				if date == anchor {
					anchor_position = Some(count)
				}
				count = count + 1
			}
			day = day + 1
		}
		match anchor_position {
			Some(position) => if !selected(spec.by_set_pos, position, count) {
				return Err(UnsynchronizedStart)
			}
			None => return Err(UnsynchronizedStart)
		}
		Ok({ anchor, pattern, termination: spec.termination, positions: spec.by_set_pos, inclusions: sorted_unique(spec.inclusions), exclusions: sorted_unique(spec.exclusions) })
	}

	## Bind a fresh cursor to this exact immutable rule and a finite half-open
	## date window. Evaluation starts at the series anchor, preserving COUNT.
	cursor : DateRecurrence, Window -> Try(Cursor, [EmptyWindow, ReversedWindow, ..])
	cursor = |rule, window| {
		if window.start == window.end {
			return Err(EmptyWindow)
		}
		if window.start > window.end {
			return Err(ReversedWindow)
		}
		Ok({ rule, window, period: 0, phase: StartPeriod, buffer: [], count: 0, pending: None, inclusion: 0 })
	}

	## Cursor representation is private. Resume accepts no replacement rule or
	## window, so a cursor cannot accidentally be used with stale inputs.
	Cursor :: {
		rule : DateRecurrence,
		window : Window,
		period : U64,
		phase : [StartPeriod, Scan({ day : I64, end : I64 }), Emit({ index : U64, end : I64 }), Done],
		buffer : List(GregorianDate),
		count : U64,
		pending : [None, Some(GregorianDate)],
		inclusion : U64,
	}.{

		## One step examines one date, buffered candidate, explicit date, or
		## period/state boundary. Each step has bounded selector/calendar work.
		## Buffer capacity counts retained candidates (at most 366); it is not
		## an allocation-byte claim. Output and immutable input lists are separate.
		## A zero budget is valid and can return Limited without advancing.
		## Reducing capacity below an already retained buffer returns BufferLimit
		## without advancing; Batch.buffered reports that existing retained count.
		## Shared cursors may copy a period buffer; no scan hides inside one step.
		collect : Cursor, Limits -> Try(Batch, [OutOfRange, ..])
		collect = |initial, limits| {
			batch = fold(initial, limits, [], |dates, date| Continue(dates.append(date)))?
			status = match batch.status {
				Complete => Complete
				Limited(progress) => Limited(progress)
				Stopped(_) => crash "Collection visitor never stops"
			}
			Ok({ dates: batch.value, steps: batch.steps, buffered: batch.buffered, status })
		}

		## Fold visits ordered, deduplicated dates after exclusions and query
		## filtering. Stop(value) consumes that date and returns its exact next
		## cursor, without searching ahead. Stopped never claims completeness.
		## max_occurrences limits visitor calls; steps account for engine work,
		## not the caller's visitor. No intermediate output list is constructed.
		## Resume with the returned cursor and value to preserve the accumulator.
		fold : Cursor, Limits, acc, (acc, GregorianDate -> [Continue(acc), Stop(acc)]) -> Try(FoldBatch(acc), [OutOfRange, ..])
		fold = |initial, limits, initial_value, visit| {
			var state = initial
			var value = initial_value
			var occurrences = 0.U64
			var steps = 0.U64
			while True {
				if buffered_count(state) > limits.max_buffered {
					return Ok(limited(state, value, occurrences, steps, BufferLimit))
				}
				explicit = List.get(state.rule.inclusions, state.inclusion)
				if state.phase == Done and state.pending == None {
					match explicit {
						Err(_) => return Ok({ value, occurrences, steps, buffered: buffered_count(state), status: Complete })
						Ok(date) => if date >= state.window.end {
							return Ok({ value, occurrences, steps, buffered: buffered_count(state), status: Complete })
						}
					}
				}
				if steps == limits.max_steps {
					return Ok(limited(state, value, occurrences, steps, WorkLimit))
				}
				steps = steps + 1
				# Merge only once the next rule date is known (or exhausted).
				if state.pending != None or state.phase == Done {
					choice = match (state.pending, explicit) {
						(Some(a), Ok(b)) => if a < b {
							a
						} else {
							b
						}
						(Some(a), Err(_)) => a
						(None, Ok(b)) => b
						(None, Err(_)) => crash "Completed merge handled above"
					}
					visible = choice >= state.window.start and choice < state.window.end and !contains(state.rule.exclusions, choice)
					if visible and occurrences == limits.max_occurrences {
						return Ok(limited(state, value, occurrences, steps, OutputLimit))
					}
					if state.pending == Some(choice) {
						state = { ..state, pending: None }
					}
					match explicit {
						Ok(date) => if date == choice {
							state = { ..state, inclusion: state.inclusion + 1 }
						}
						Err(_) => {}
					}
					if visible {
						occurrences = occurrences + 1
						match visit(value, choice) {
							Continue(updated) => {
								value = updated
							}
							Stop(updated) => return Ok({ value: updated, occurrences, steps, buffered: buffered_count(state), status: Stopped(state) })
						}
					}
				} else {
					match state.phase {
						StartPeriod => {
							frame = CalendarPattern.period(state.rule.pattern, state.period)?
							stop = frame.start >= state.window.end or match state.rule.termination {
								Until(end) => frame.start > end
								Count(count) => state.count >= count
								Forever => False
							}
							state = if stop {
								{ ..state, phase: Done, buffer: [] }
							} else {
								{ ..state, phase: Scan({ day: number(frame.start), end: number(frame.end) }) }
							}
						}
						Scan(scan) => {
							if scan.day == scan.end {
								state = { ..state, phase: Emit({ index: 0, end: scan.end }) }
							} else {
								date = from_number(scan.day)?
								if CalendarPattern.matches(state.rule.pattern, state.period, date)? {
									if state.buffer.len() == limits.max_buffered {
										return Ok(limited(state, value, occurrences, steps, BufferLimit))
									}
									state = { ..state, buffer: state.buffer.append(date) }
								}
								state = { ..state, phase: Scan({ ..scan, day: scan.day + 1 }) }
							}
						}
						Emit(emission) => {
							index = emission.index
							match List.get(state.buffer, index) {
								Err(_) => {
									# The finite Gregorian period count is far below U64.highest.
									stop = emission.end >= number(state.window.end) or match state.rule.termination {
										Until(end) => emission.end > number(end)
										_ => False
									}
									state = {
										..state,
										period: state.period + 1,
										phase: if stop {
											Done
										} else {
											StartPeriod
										},
										buffer: [],
									}
								}
								Ok(date) => {
									chosen = selected(state.rule.positions, index, state.buffer.len()) and date >= state.rule.anchor
									state = { ..state, phase: Emit({ ..emission, index: index + 1 }) }
									if chosen {
										stop = date >= state.window.end or match state.rule.termination {
											Until(end) => date > end
											Count(count) => state.count >= count
											Forever => False
										}
										if stop {
											state = { ..state, phase: Done, buffer: [] }
										} else {
											# At most one counted date per provider day; even the full
											# Gregorian provider contains far fewer than U64.highest.
											state = { ..state, pending: Some(date), count: state.count + 1 }
											match state.rule.termination {
												Count(count) => if state.count == count {
													state = { ..state, phase: Done, buffer: [] }
												}
												_ => {}
											}
										}
									}
								}
							}
						}
						Done => crash "Completed rule handled by merge"
					}
				}
			}
			crash "Recurrence loop returns a batch"
		}

		## Return one date without looking for the following date. End is proven
		## exhaustion; Limited needs more work/capacity and is not end-of-series.
		next : Cursor, { max_steps : U64, max_buffered : U64 } -> Try(Next, [OutOfRange, ..])
		next = |initial, budget| {
			batch = fold(initial, { max_steps: budget.max_steps, max_buffered: budget.max_buffered, max_occurrences: 1 }, None, |_, date| Stop(Some(date)))?
			status = match batch.status {
				Complete => End
				Limited(progress) => Limited(progress)
				Stopped(remaining) => match batch.value {
					Some(date) => Item({ date, cursor: remaining })
					None => crash "Next visitor stops with a date"
				}
			}
			Ok({ steps: batch.steps, buffered: batch.buffered, status })
		}

		## Lazy Roc iterator of bounded batches. Each advance performs one collect;
		## no series expansion happens while constructing this iterator.
		## Complete, Limited and errors remain visible items. Iter exhaustion is
		## transport exhaustion, not proof that the temporal query completed.
		## Positive work/output limits continue automatically. BufferLimit or a
		## zero work/output budget emits one terminal Limited item; its cursor can
		## be resumed explicitly with larger limits. Errors are emitted once.
		## Retaining chunks/rest iterators can retain their captured buffers.
		chunks : Cursor, Limits -> Iter(Try(Batch, [OutOfRange]))
		chunks = |initial, limits| Iter.custom(
			Active(initial),
			Unknown,
			|state| match state {
				Finished => Err(NoMore)
				Active(current) => {
					result = collect(current, limits)
					remaining = match result {
						Err(_) => Finished
						Ok(batch) => match batch.status {
							Complete => Finished
							Limited(progress) => if progress.reason == BufferLimit or limits.max_steps == 0 or limits.max_occurrences == 0 {
								Finished
							} else {
								Active(progress.cursor)
							}
						}
					}
					Ok((result, remaining))
				}
			},
		)

		to_inspect : Cursor -> Str
		to_inspect = |state| "DateRecurrence.Cursor(period=${state.period.to_str()}, counted=${state.count.to_str()}, buffered=${buffered_count(state).to_str()})"
	}

	to_inspect : DateRecurrence -> Str
	to_inspect = |rule| "DateRecurrence(anchor=${Str.inspect(rule.anchor)}, termination=${Str.inspect(rule.termination)})"
}

number = |date| CivilDay.to_day_number(GregorianDate.to_civil_day(date))

from_number = |day| GregorianDate.from_civil_day(CivilDay.from_day_number(day))

selected : List(I16), U64, U64 -> Bool
selected = |positions, index, count| {
	if positions.is_empty() {
		return True
	}
	# A Gregorian period contains at most 366 dates, so narrowing is exact.
	positive = index.to_i64_wrap() + 1
	negative = index.to_i64_wrap() - count.to_i64_wrap()
	var found = False
	for position in positions {
		found = found or position.to_i64() == positive or position.to_i64() == negative
	}
	found
}

limited : DateRecurrence.Cursor, acc, U64, U64, DateRecurrence.Limit -> DateRecurrence.FoldBatch(acc)
limited = |cursor, value, occurrences, steps, reason| {
	value,
	occurrences,
	steps,
	buffered: buffered_count(cursor),
	status: Limited({ cursor, reason }),
}

sorted_unique = |dates| {
	ordered = dates.sort_with(
		|a, b| if a < b {
			Before
		} else if a > b {
			After
		} else {
			Same
		},
	)
	var result = []
	var previous = None
	for date in ordered {
		if previous != Some(date) {
			result = result.append(date)
		}
		previous = Some(date)
	}
	result
}

contains : List(GregorianDate), GregorianDate -> Bool
contains = |dates, date| {
	var low = 0.U64
	var high = dates.len()
	while low < high {
		middle = low + U64.div_trunc_by(high - low, 2)
		value = match List.get(dates, middle) {
			Ok(v) => v
			Err(_) => crash "Binary search bounds"
		}
		if value < date {
			low = middle + 1
		} else if value > date {
			high = middle
		} else {
			return True
		}
	}
	False
}

# A pending date normally also belongs to the period buffer. COUNT can release
# that buffer before the merge emits the pending date, which still occupies one
# candidate slot. Count distinct retained candidates, not duplicate references.
buffered_count : DateRecurrence.Cursor -> U64
buffered_count = |cursor| if cursor.buffer.is_empty() and cursor.pending != None {
	1
} else {
	cursor.buffer.len()
}
