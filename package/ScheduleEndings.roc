import TimedOccurrence
import LocalDateTime
import PosixDelta
import CalendarDelta

# Internal validated ending definitions, shared by schedule construction and
# window-free declarations. No zone resolution or candidate enumeration.
ScheduleEndings :: { duration : TimedOccurrence.Duration, overrides : List(Override) }.{
	Override : { source : LocalDateTime, ending : TimedOccurrence.Ending }
	Error : [InvalidDuration, TooManyOverrides, ConflictingEnding(LocalDateTime)]
	normalize : List(Override) -> Try(List(Override), [InvalidDuration, TooManyOverrides, ConflictingEnding(LocalDateTime), ..])
	normalize = normalize_endings
	new : TimedOccurrence.Duration, List(Override) -> Try(ScheduleEndings, [InvalidDuration, TooManyOverrides, ConflictingEnding(LocalDateTime), ..])
	new = |duration, inputs| {
		overrides = normalize_endings(inputs)?
		TimedOccurrence.validate_duration(duration)?
		Ok({ duration, overrides })
	}
	definition : ScheduleEndings -> { duration : TimedOccurrence.Duration, overrides : List(Override) }
	definition = |value| { duration: value.duration, overrides: value.overrides }
}

normalize_endings : List(ScheduleEndings.Override) -> Try(List(ScheduleEndings.Override), [InvalidDuration, TooManyOverrides, ConflictingEnding(LocalDateTime), ..])
normalize_endings = |inputs| {
	if inputs.len() > 4096 {
		return Err(TooManyOverrides)
	}
	for input in inputs {
		match input.ending {
			After(duration) => {
				TimedOccurrence.validate_duration(duration)?
			}
			_ => {}
		}
	}
	sorted = inputs.sort_with(
		|a, b| match LocalDateTime.compare_position(a.source, b.source) {
			LT => Before
			EQ => Same
			GT => After
		},
	)
	var $result = []
	var $previous = None
	for input in sorted {
		distinct = match $previous {
			None => Bool.True
			Some(value) => if LocalDateTime.same_position(value.source, input.source) {
				if !same_ending_definition(value.ending, input.ending) {
					return Err(ConflictingEnding(input.source))
				}
				Bool.False
			} else {
				Bool.True
			}
		}
		if distinct {
			$result = $result.append(input)
		}
		$previous = Some(input)
	}
	Ok($result)
}

same_ending_definition : TimedOccurrence.Ending, TimedOccurrence.Ending -> Bool
same_ending_definition = |a, b| match (a, b) {
	(After(left), After(right)) => same_duration_definition(left, right)
	(AtBoundary(left), AtBoundary(right)) => left == right
	(AtLocal(left), AtLocal(right)) => left.source == right.source and left.occurrence == right.occurrence and left.gap == right.gap
	_ => Bool.False
}

# Compare input meaning, not the extent of a particular resolved occurrence.
same_duration_definition : TimedOccurrence.Duration, TimedOccurrence.Duration -> Bool
same_duration_definition = |left, right| match (left, right) {
	(Coordinate(a), Coordinate(b)) => PosixDelta.to_microseconds(a) == PosixDelta.to_microseconds(b)
	(Calendar(a), Calendar(b)) => {
		x = CalendarDelta.to_components(a.delta)
		y = CalendarDelta.to_components(b.delta)
		x.years == y.years and x.months == y.months and x.days == y.days and a.invalid_date == b.invalid_date and a.tail == b.tail and a.occurrence == b.occurrence and a.gap == b.gap
	}
	_ => Bool.False
}
