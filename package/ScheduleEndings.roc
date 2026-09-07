import TimedOccurrence
import LocalDateTime
import PosixDelta
import CalendarDelta
import ZoneRules
import FixedOffset

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
	is_eq : ScheduleEndings, ScheduleEndings -> Bool
	is_eq = |a, b| {
		if !same_duration_definition(a.duration, b.duration) or a.overrides.len() != b.overrides.len() {
			return Bool.False
		}
		var $index = 0.U64
		while $index < a.overrides.len() {
			left = a.overrides.get($index) ?? crash "validated equal list lengths"
			right = b.overrides.get($index) ?? crash "validated equal list lengths"
			if left.source != right.source or !same_ending_definition(left.ending, right.ending) {
				return Bool.False
			}
			$index = $index + 1
		}
		Bool.True
	}
	to_hash : ScheduleEndings, Hasher -> Hasher
	to_hash = |value, hasher| {
		var $hash = value.overrides.len().to_hash(hash_duration(value.duration, hasher))
		for entry in value.overrides {
			$hash = hash_ending(entry.ending, entry.source.to_hash($hash))
		}
		$hash
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

# Tagged field hashing mirrors declaration equality without materializing keys.
hash_duration : TimedOccurrence.Duration, Hasher -> Hasher
hash_duration = |duration, hasher| match duration {
	Coordinate(value) => PosixDelta.to_microseconds(value).to_hash((0.U8).to_hash(hasher))
	Calendar(value) => {
		parts = CalendarDelta.to_components(value.delta)
		base = parts.days.to_hash(parts.months.to_hash(parts.years.to_hash((1.U8).to_hash(hasher))))
		policy : U8
		policy = match value.invalid_date {
			Reject => 0
			Clamp => 1
			Carry => 2
		}
		tail = PosixDelta.to_microseconds(value.tail).to_hash(policy.to_hash(base))
		hash_gap(value.gap, hash_occurrence(value.occurrence, tail))
	}
}

hash_ending : TimedOccurrence.Ending, Hasher -> Hasher
hash_ending = |ending, hasher| match ending {
	After(duration) => hash_duration(duration, (0.U8).to_hash(hasher))
	AtBoundary(point) => point.to_hash((1.U8).to_hash(hasher))
	AtLocal(value) => hash_gap(value.gap, hash_occurrence(value.occurrence, value.source.to_hash((2.U8).to_hash(hasher))))
}

hash_occurrence : ZoneRules.OccurrencePolicy, Hasher -> Hasher
hash_occurrence = |policy, hasher| match policy {
	RequireUnique => (0.U8).to_hash(hasher)
	First => (1.U8).to_hash(hasher)
	Last => (2.U8).to_hash(hasher)
	MatchingOffset(offset) => FixedOffset.to_seconds(offset).to_hash((3.U8).to_hash(hasher))
}

hash_gap : [RejectGap, UseOffsetBeforeGap], Hasher -> Hasher
hash_gap = |policy, hasher| match policy {
	RejectGap => (0.U8).to_hash(hasher)
	UseOffsetBeforeGap => (1.U8).to_hash(hasher)
}
