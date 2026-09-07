import TimedOccurrence
import TimedSchedule
import CalendarDelta
import CalendarArithmetic
import ZoneRules
import FixedOffset
import PosixDelta
import PosixBoundary
import PersistenceRules
import PersistenceLocal

# Internal ending/policy blocks for timed-schedule-definition-v1. Coordinate
# duration: coordinate, signed microseconds. Calendar duration: calendar, years,
# months, days, reject|clamp|carry, signed tail microseconds, occurrence pair,
# reject|before. Occurrence pair: unique|first|last plus empty reserved field,
# or offset plus signed I32 seconds. All integers have canonical spelling.
# Overrides: count, then (source local label, after + duration | boundary + I64
# microseconds | local + local label + occurrence pair + gap) for each entry.
# Source and endpoint labels use PersistenceLocal, retaining calendar identity.
PersistenceEndings :: [].{
	Error : [Malformed, InvalidInteger, OutOfRange, TooManyOverrides, InvalidDuration, Local(PersistenceLocal.Error)]
	duration_fields : TimedOccurrence.Duration -> List(Str)
	duration_fields = |duration| match duration {
		Coordinate(delta) => ["coordinate", PosixDelta.to_microseconds(delta).to_str()]
		Calendar(value) => {
			parts = CalendarDelta.to_components(value.delta)
			["calendar", parts.years.to_str(), parts.months.to_str(), parts.days.to_str(), date_policy_text(value.invalid_date), PosixDelta.to_microseconds(value.tail).to_str()].concat(occurrence_fields(value.occurrence)).append(gap_text(value.gap))
		}
	}
	parse_duration : List(Str) -> Try({ value : TimedOccurrence.Duration, rest : List(Str) }, Error)
	parse_duration = |fields| {
		kind = at(fields, 0)?
		(value, consumed) = match kind {
			"coordinate" => (Coordinate(PosixDelta.from_microseconds(integer(at(fields, 1)?)?)), 2.U64)
			"calendar" => {
				years = integer(at(fields, 1)?)?
				months = integer(at(fields, 2)?)?
				days = integer(at(fields, 3)?)?
				invalid_date = date_policy(at(fields, 4)?)?
				tail = PosixDelta.from_microseconds(integer(at(fields, 5)?)?)
				occurrence = parse_occurrence(at(fields, 6)?, at(fields, 7)?)?
				gap = parse_gap(at(fields, 8)?)?
				(Calendar({ delta: CalendarDelta.from_components({ years, months, days }), invalid_date, tail, occurrence, gap }), 9.U64)
			}
			_ => return Err(Malformed)
		}
		TimedOccurrence.validate_duration(value)?
		Ok({ value, rest: fields.drop_first(consumed) })
	}
	occurrence_fields : ZoneRules.OccurrencePolicy -> List(Str)
	occurrence_fields = |policy| match policy {
		RequireUnique => ["unique", ""]
		First => ["first", ""]
		Last => ["last", ""]
		MatchingOffset(offset) => ["offset", FixedOffset.to_seconds(offset).to_str()]
	}
	parse_occurrence : Str, Str -> Try(ZoneRules.OccurrencePolicy, Error)
	parse_occurrence = |kind, offset| {
		if kind != "offset" and !offset.is_empty() {
			return Err(Malformed)
		}
		match kind {
			"unique" => Ok(RequireUnique)
			"first" => Ok(First)
			"last" => Ok(Last)
			"offset" => {
				seconds = integer(offset)?
				if seconds < -2147483648 or seconds > 2147483647 {
					return Err(OutOfRange)
				}
				Ok(MatchingOffset(FixedOffset.from_seconds(seconds.to_i32_wrap())))
			}
			_ => Err(Malformed)
		}
	}
	gap_text : [RejectGap, UseOffsetBeforeGap] -> Str
	gap_text = |gap| match gap {
		RejectGap => "reject"
		UseOffsetBeforeGap => "before"
	}
	parse_gap : Str -> Try([RejectGap, UseOffsetBeforeGap], Error)
	parse_gap = |text| match text {
		"reject" => Ok(RejectGap)
		"before" => Ok(UseOffsetBeforeGap)
		_ => Err(Malformed)
	}
	to_fields : TimedOccurrence.Duration, List(TimedSchedule.EndOverride) -> Try(List(Str), Error)
	to_fields = |duration, overrides| {
		if overrides.len() > 1024 {
			return Err(TooManyOverrides)
		}
		var $fields = duration_fields(duration).append(overrides.len().to_str())
		for entry in overrides {
			ending_fields = match entry.ending {
				After(value) => {
					["after"].concat(duration_fields(value))
				}
				AtBoundary(boundary) => {
					["boundary", PosixBoundary.to_microseconds(boundary).to_str()]
				}
				AtLocal(value) => {
					["local", PersistenceLocal.to_text(value.source)].concat(occurrence_fields(value.occurrence)).append(gap_text(value.gap))
				}
			}
			# Keep the match independent of the growing output buffer; see
			# tests/compiler_repro/list_append_match_concat for the pinned compiler
			# corruption regression. Simple append growth avoids repeated copying
			# of the full prefix while retaining linear work in encoded fields.
			$fields = $fields.append(PersistenceLocal.to_text(entry.source))
			for field in ending_fields {
				$fields = $fields.append(field)
			}
		}
		Ok($fields)
	}
	from_fields : List(Str) -> Try({ duration : TimedOccurrence.Duration, overrides : List(TimedSchedule.EndOverride), rest : List(Str) }, Error)
	from_fields = |fields| {
		parsed = parse_duration(fields)?
		count = integer(at(parsed.rest, 0)?)?
		if count < 0 {
			return Err(InvalidInteger)
		}
		if count > 1024 {
			return Err(TooManyOverrides)
		}
		var $rest = parsed.rest.drop_first(1)
		var $overrides = []
		var $index = 0.I64
		while $index < count {
			source = local_value(at($rest, 0)?)?
			kind = at($rest, 1)?
			$rest = $rest.drop_first(2)
			ending = match kind {
				"after" => {
					inner = parse_duration($rest)?
					$rest = inner.rest
					After(inner.value)
				}
				"boundary" => {
					boundary = PosixBoundary.from_microseconds(integer(at($rest, 0)?)?)
					$rest = $rest.drop_first(1)
					AtBoundary(boundary)
				}
				"local" => {
					end = local_value(at($rest, 0)?)?
					occurrence = parse_occurrence(at($rest, 1)?, at($rest, 2)?)?
					gap = parse_gap(at($rest, 3)?)?
					$rest = $rest.drop_first(4)
					AtLocal({ source: end, occurrence, gap })
				}
				_ => return Err(Malformed)
			}
			$overrides = $overrides.append({ source, ending })
			$index = $index + 1
		}
		Ok({ duration: parsed.value, overrides: $overrides, rest: $rest })
	}
}

at = |fields, index| match fields.get(index) {
	Ok(value) => Ok(value)
	Err(_) => Err(Malformed)
}

integer = |text| match PersistenceRules.integer(text) {
	Ok(value) => Ok(value)
	Err(OutOfRange) => Err(OutOfRange)
	Err(_) => Err(InvalidInteger)
}

date_policy_text : CalendarArithmetic.Policy -> Str
date_policy_text = |policy| match policy {
	Reject => "reject"
	Clamp => "clamp"
	Carry => "carry"
}

date_policy = |text| match text {
	"reject" => Ok(Reject)
	"clamp" => Ok(Clamp)
	"carry" => Ok(Carry)
	_ => Err(Malformed)
}

local_value = |text| match PersistenceLocal.parse(text) {
	Ok(value) => Ok(value)
	Err(error) => Err(Local(error))
}
