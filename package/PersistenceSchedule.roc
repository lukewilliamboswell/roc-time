import ScheduleDefinition
import TimedRecurrence
import ICalTimedRule
import ICalDuration
import ICalPeriod
import PersistenceRecurrence
import PersistenceEndings
import PersistenceRules
import PersistenceFields
import PersistenceEnvelope
import PersistenceLocal
import CalendarDelta
import PosixDelta
import PosixBoundary
import FixedOffset
import ZoneRules

## Internal timed-schedule-definition-v1 payload transport. Flat JSON string
## array grammar: native|ical, PersistenceRecurrence block, then origin fields.
## Native: PersistenceEndings duration/overrides block, occurrence kind/offset,
## gap, rules, complete PersistenceRules block. iCalendar: profile, mode
## utc|floating|zoned, canonical duration, PERIOD count, canonical PERIOD values,
## then utc alone or rules followed by the complete rule block. No trailing
## fields. The profile must equal rfc5545-timed-values-v1. There is no inner
## version: the enclosing envelope declares timed-schedule-definition-v1.
##
## Counts and integers have canonical decimal spelling. Calendar identity,
## microseconds, native selector order/duplicates, ending intent, PERIOD order,
## origin, policies and complete immutable interpretation rules survive. Never
## read a host clock/database, choose a query window, or enumerate occurrences.
## Input/output caps: 49152 payload bytes, 65536 escaped envelope bytes, 4096
## combined selectors, 1024 combined recurrence exceptions, 1024 overrides or
## PERIODs, 1024 transitions and 4096 combined rule metadata bytes. Native
## construction validates once through existing definition constructors.
## Cached canonical text gives bounded declaration equality without execution.
PersistenceSchedule :: { stored : ScheduleDefinition, text : Str }.{
	Error : [TooLarge, Malformed, UnsupportedOrigin, UnsupportedProfile, TooManyOverrides, InvalidInteger, OutOfRange, Recurrence(PersistenceRecurrence.Error), Endings(PersistenceEndings.Error), Rules(PersistenceRules.Error), InvalidICalDuration(ICalDuration.Error), InvalidICalPeriod(ICalPeriod.Error), InvalidICalRule(ICalTimedRule.Error), InvalidDefinition(ScheduleDefinition.Error)]
	from_definition : ScheduleDefinition -> Try(PersistenceSchedule, Error)
	from_definition = |stored| {
		fields = match ScheduleDefinition.definition(stored) {
			Native(spec) => {
				if spec.overrides.len() > 1024 {
					return Err(TooManyOverrides)
				}
				if !PersistenceRecurrence.fits(spec.rule) or !PersistenceRules.fits(spec.context.rules) {
					return Err(TooLarge)
				}
				recurrence = recurrence_fields(spec.rule)?
				endings = match PersistenceEndings.to_fields(spec.duration, spec.overrides) {
					Ok(value) => value
					Err(error) => return Err(Endings(error))
				}
				["native"].concat(recurrence).concat(endings).concat(PersistenceEndings.occurrence_fields(spec.context.occurrence)).append(PersistenceEndings.gap_text(spec.context.gap)).append("rules").concat(PersistenceRules.to_fields(spec.context.rules))
			}
			ICal(spec) => {
				data = ICalTimedRule.definition(spec.rule)
				if data.periods.len() > 1024 {
					return Err(TooManyOverrides)
				}
				if !PersistenceRecurrence.fits(data.rule) {
					return Err(TooLarge)
				}
				match spec.context {
					Utc => {}
					Local(rules) => if !PersistenceRules.fits(rules) {
						return Err(TooLarge)
					}
				}
				mode = match data.mode {
					Utc => "utc"
					Floating => "floating"
					Zoned => "zoned"
				}
				base = ["ical"].concat(recurrence_fields(data.rule)?).concat([ICalTimedRule.profile, mode, ICalDuration.to_text(data.duration), data.periods.len().to_str()]).concat(data.periods.map(ICalPeriod.to_text))
				match spec.context {
					Utc => base.append("utc")
					Local(rules) => base.append("rules").concat(PersistenceRules.to_fields(rules))
				}
			}
		}
		text = Json.to_str(fields)
		if text.count_utf8_bytes() > 49152 {
			return Err(TooLarge)
		}
		match PersistenceEnvelope.new({ format: "roc-time", version: "1", kind: "schedule-definition", profile: "timed-schedule-definition-v1", axis: "posix-1970", unit: "microsecond", payload: text }) {
			Ok(_) => Ok({ stored, text })
			Err(_) => Err(TooLarge)
		}
	}
	definition : PersistenceSchedule -> ScheduleDefinition
	definition = |value| value.stored
	to_text : PersistenceSchedule -> Str
	to_text = |value| value.text
	is_eq : PersistenceSchedule, PersistenceSchedule -> Bool
	is_eq = |a, b| a.text == b.text
	to_hash : PersistenceSchedule, Hasher -> Hasher
	to_hash = |value, hasher| value.text.to_hash(hasher)
	parse : Str -> Try(PersistenceSchedule, Error)
	parse = |text| {
		if text.count_utf8_bytes() > 49152 {
			return Err(TooLarge)
		}
		decoded : Try(Fields, [InvalidJson(Str), Encoding([InvalidJson(Str)]), TooManyFields, UnsupportedContainer])
		decoded = Json.parse(text)
		fields = match decoded {
			Ok(value) => Fields.values(value)
			Err(TooManyFields) => return Err(TooLarge)
			Err(_) => return Err(Malformed)
		}
		origin = at(fields, 0)?
		if origin != "native" and origin != "ical" {
			return Err(UnsupportedOrigin)
		}
		recurrence = match PersistenceRecurrence.from_fields(fields.drop_first(1)) {
			Ok(value) => value
			Err(error) => return Err(Recurrence(error))
		}
		stored = if origin == "native" {
			endings = match PersistenceEndings.from_fields(recurrence.rest) {
				Ok(value) => value
				Err(error) => return Err(Endings(error))
			}
			occurrence = match PersistenceEndings.parse_occurrence(at(endings.rest, 0)?, at(endings.rest, 1)?) {
				Ok(value) => value
				Err(error) => return Err(Endings(error))
			}
			gap = match PersistenceEndings.parse_gap(at(endings.rest, 2)?) {
				Ok(value) => value
				Err(error) => return Err(Endings(error))
			}
			if at(endings.rest, 3)? != "rules" {
				return Err(Malformed)
			}
			rules = rules_value(endings.rest.drop_first(4))?
			match ScheduleDefinition.from_native({ rule: recurrence.value, duration: endings.duration, overrides: endings.overrides, context: { rules, occurrence, gap } }) {
				Ok(value) => value
				Err(error) => return Err(InvalidDefinition(error))
			}
		} else {
			if at(recurrence.rest, 0)? != ICalTimedRule.profile {
				return Err(UnsupportedProfile)
			}
			mode = match at(recurrence.rest, 1)? {
				"utc" => Utc
				"floating" => Floating
				"zoned" => Zoned
				_ => return Err(Malformed)
			}
			count = integer(at(recurrence.rest, 3)?)?
			if count < 0 {
				return Err(InvalidInteger)
			}
			if count > 1024 {
				return Err(TooManyOverrides)
			}
			if recurrence.rest.len() < 5 + count.to_u64_wrap() {
				return Err(Malformed)
			}
			duration = match ICalDuration.parse(at(recurrence.rest, 2)?) {
				Ok(value) => value
				Err(error) => return Err(InvalidICalDuration(error))
			}
			var $periods = []
			for field in recurrence.rest.drop_first(4).take_first(count.to_u64_wrap()) {
				period = match ICalPeriod.parse(field) {
					Ok(value) => value
					Err(error) => return Err(InvalidICalPeriod(error))
				}
				$periods = $periods.append(period)
			}
			remaining = recurrence.rest.drop_first(4 + count.to_u64_wrap())
			context = match at(remaining, 0)? {
				"utc" => {
					if remaining.len() != 1 {
						return Err(Malformed)
					}
					Utc
				}
				"rules" => Local(rules_value(remaining.drop_first(1))?)
				_ => return Err(Malformed)
			}
			rule = match ICalTimedRule.new({ rule: recurrence.value, duration, periods: $periods, mode }) {
				Ok(value) => value
				Err(error) => return Err(InvalidICalRule(error))
			}
			match ScheduleDefinition.from_ical({ rule, context }) {
				Ok(value) => value
				Err(error) => return Err(InvalidDefinition(error))
			}
		}
		from_definition(stored)
	}
	Fields :: { values : List(Str) }.{
		values : Fields -> List(Str)
		values = |fields| fields.values
		parser_for : encoding -> (state -> Try({ value : Fields, rest : state }, [Encoding(err), TooManyFields, UnsupportedContainer, ..]))
			where [
				encoding.parse_list_start : encoding, state -> Try([Counted({ len : U64, rest : state }), Uncounted(state)], err),
				encoding.parse_list_next : encoding, state -> Try([Item(state), Done(state)], err),
				encoding.parse_str : encoding, state -> Try({ value : Str, rest : state }, err),
				encoding.parse_list_after_item : encoding, state -> Try([Continue(state), Done(state)], err),
			]
		parser_for = |encoding| {
			# 49152 bytes admit at most 16384 minimally encoded string fields.
			parse_fields = PersistenceFields.parser(encoding, 16384)
			|state| {
				parsed = parse_fields(state)?
				Ok({ value: { values: parsed.value }, rest: parsed.rest })
			}
		}
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

rules_value = |fields| match PersistenceRules.from_fields(fields) {
	Ok(value) => Ok(value)
	Err(error) => Err(Rules(error))
}

recurrence_fields = |rule| match PersistenceRecurrence.to_fields(rule) {
	Ok(value) => Ok(value)
	Err(error) => Err(Recurrence(error))
}

# Hand-authored native declaration transport. Full U64 COUNT and signed axis
# extremes are source facts, not measurements or outputs from this encoder.
test_recurrence = |fraction, hour, count| ["gregorian;fraction;1970;1;1;${hour};0;0;6;${fraction}", "calendar", "daily", "1", "mo", "", "", "", "", "", hour, "0", "0", "", "count", count, "0", "0"]

test_rules = ["Fixture/UTC", "v1", "-9223372036854775808", "9223372036854775807", "0", "-3600", "3600", "supplied", "", "", "", "", "0"]

test_native_fields = || ["native"].concat(test_recurrence("123", "0", "18446744073709551615")).concat([
	"calendar",
	"0",
	"1",
	"2",
	"clamp",
	"500",
	"offset",
	"3600",
	"before",
	"3",
	"gregorian;fraction;1970;1;1;0;0;0;6;123",
	"after",
	"coordinate",
	"1",
	"gregorian;fraction;1970;1;2;0;0;0;6;123",
	"boundary",
	"9223372036854775807",
	"gregorian;fraction;1970;1;3;0;0;0;6;123",
	"local",
	"julian;fraction;1969;12;22;0;0;0;6;456",
	"first",
	"",
	"reject",
	"last",
	"",
	"reject",
	"rules",
]).concat(test_rules)

expect {
	fields = test_native_fields()
	archive = PersistenceSchedule.parse(Json.to_str(fields))?
	native = match ScheduleDefinition.definition(PersistenceSchedule.definition(archive)) {
		Native(value) => value
		ICal(_) => crash "native fixture origin"
	}
	data = TimedRecurrence.definition(native.rule)
	duration_valid = match native.duration {
		Calendar(value) => CalendarDelta.to_components(value.delta) == { years: 0, months: 1, days: 2 } and value.invalid_date == Clamp and value.tail == PosixDelta.from_microseconds(500) and value.occurrence == MatchingOffset(FixedOffset.from_seconds(3600)) and value.gap == UseOffsetBeforeGap
		_ => Bool.False
	}
	endings_valid = match native.overrides {
		[first, second, third] => match (first.ending, second.ending, third.ending) {
			(After(Coordinate(delta)), AtBoundary(boundary), AtLocal(local)) => delta == PosixDelta.from_microseconds(1) and boundary == PosixBoundary.from_microseconds(I64.highest) and PersistenceLocal.to_text(local.source) == "julian;fraction;1969;12;22;0;0;0;6;456" and local.occurrence == First and local.gap == RejectGap
			_ => Bool.False
		}
		_ => Bool.False
	}
	data.termination == Count(U64.highest) and PersistenceLocal.to_text(data.anchor) == "gregorian;fraction;1970;1;1;0;0;0;6;123" and duration_valid and endings_valid and native.context.occurrence == Last and native.context.gap == RejectGap and ZoneRules.definition(native.context.rules).version == "v1" and PersistenceSchedule.to_text(archive) == Json.to_str(fields) and PersistenceSchedule.from_definition(PersistenceSchedule.definition(archive))? == archive
}

test_ical_fields = || ["ical"].concat(test_recurrence("0", "9", "2")).concat(["rfc5545-timed-values-v1", "utc", "PT3600S", "2", "19700102T090000Z/PT7200S", "19700103T090000Z/19700103T103000Z", "utc"])

expect {
	fields = test_ical_fields()
	archive = PersistenceSchedule.parse(Json.to_str(fields))?
	origin = match ScheduleDefinition.definition(PersistenceSchedule.definition(archive)) {
		ICal(spec) => {
			data = ICalTimedRule.definition(spec.rule)
			data.mode == Utc and ICalDuration.components(data.duration) == { days: 0, seconds: 3600 } and data.periods.map(ICalPeriod.to_text) == ["19700102T090000Z/PT7200S", "19700103T090000Z/19700103T103000Z"] and match spec.context {
				Utc => Bool.True
				Local(_) => Bool.False
			}
		}
		Native(_) => Bool.False
	}
	origin and PersistenceSchedule.to_text(archive) == Json.to_str(fields)
}

test_status = |fields| match PersistenceSchedule.parse(Json.to_str(fields)) {
	Ok(_) => Ok({})
	Err(error) => Err(error)
}

expect {
	native_prefix = ["native"].concat(test_recurrence("0", "0", "1"))
	ical_prefix = ["ical"].concat(test_recurrence("0", "9", "2"))
	test_status(["native-v2"]) == Err(UnsupportedOrigin) and
		test_status(ical_prefix.concat(["rfc5545-timed-values-v2"])) == Err(UnsupportedProfile) and
			test_status(native_prefix.concat(["coordinate", "1", "1025"])) == Err(Endings(TooManyOverrides)) and
				test_status(ical_prefix.concat(["rfc5545-timed-values-v1", "utc", "bad", "1025"])) == Err(TooManyOverrides) and
					test_status(native_prefix.concat(["coordinate", "0", "0"])) == Err(Endings(InvalidDuration)) and
						test_status(native_prefix.concat(["coordinate", "1", "0", "first", "nonempty", "reject", "rules"]).concat(test_rules)) == Err(Endings(Malformed)) and
							test_status(test_ical_fields().append("trailing")) == Err(Malformed) and
								test_status(test_native_fields().drop_last(1)) == Err(Rules(Malformed))
}

# Byte fixtures are independently counted from the declared JSON grammar.
# 650 boundary overrides cost 48913 payload bytes with version v1; padding
# 239 ASCII bytes reaches 49152. A different valid declaration with 378
# calendar overrides and 4094 quote bytes in metadata has a 48795-byte payload
# but reaches the 65536-byte outer envelope through JSON escaping.
test_boundary_fields = |count, calendar, version| {
	var $fields = ["native"].concat(test_recurrence("0", "0", "1")).concat(["coordinate", "1", count.to_str()])
	var $index = 0.U64
	while $index < count {
		ending = if calendar {
			["after", "calendar", "0", "0", "1", "reject", "0", "unique", "", "reject"]
		} else {
			["boundary", "9223372036854775807"]
		}
		$fields = $fields.concat(["gregorian;fraction;1970;1;1;0;0;0;6;${$index.to_str()}"].concat(ending))
		$index = $index + 1
	}
	$fields.concat(["unique", "", "reject", "rules", "F", version, "-9223372036854775808", "9223372036854775807", "0", "0", "0", "supplied", "", "", "", "", "0"])
}

test_grow_version = |archive| {
	spec = match ScheduleDefinition.definition(PersistenceSchedule.definition(archive)) {
		Native(value) => value
		ICal(_) => crash "native size fixture"
	}
	rules = ZoneRules.definition(spec.context.rules)
	grown = ZoneRules.from_definition({ ..rules, version: rules.version.concat("A") })?
	definition = match ScheduleDefinition.from_native({ ..spec, context: { ..spec.context, rules: grown } }) {
		Ok(value) => value
		Err(error) => return Err(InvalidDefinition(error))
	}
	match PersistenceSchedule.from_definition(definition) {
		Err(TooLarge) => Ok({})
		_ => Err(ExpectedTooLarge)
	}
}

expect {
	below_text = Json.to_str(test_boundary_fields(650.U64, Bool.False, "v1".concat(Str.repeat("A", 238))))
	text = Json.to_str(test_boundary_fields(650.U64, Bool.False, "v1".concat(Str.repeat("A", 239))))
	above_text = Json.to_str(test_boundary_fields(650.U64, Bool.False, "v1".concat(Str.repeat("A", 240))))
	below = PersistenceSchedule.parse(below_text)?
	archive = PersistenceSchedule.parse(text)?
	below_text.count_utf8_bytes() == 49151 and text.count_utf8_bytes() == 49152 and above_text.count_utf8_bytes() == 49153 and PersistenceSchedule.to_text(below) == below_text and PersistenceSchedule.to_text(archive) == text and PersistenceSchedule.parse(above_text) == Err(TooLarge) and test_grow_version(archive) == Ok({})
}

expect {
	text = Json.to_str(test_boundary_fields(378.U64, Bool.True, Str.repeat("\"", 4094)))
	archive = PersistenceSchedule.parse(text)?
	envelope = PersistenceEnvelope.new({ format: "roc-time", version: "1", kind: "schedule-definition", profile: "timed-schedule-definition-v1", axis: "posix-1970", unit: "microsecond", payload: text })?
	text.count_utf8_bytes() == 48795 and PersistenceEnvelope.to_text(envelope).count_utf8_bytes() == 65536 and PersistenceSchedule.to_text(archive) == text and test_grow_version(archive) == Ok({})
}
