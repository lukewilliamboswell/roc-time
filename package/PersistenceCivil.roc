import ResolvedBoundary
import ResolvedSelection
import ZoneRules
import LocalDateTime
import Calendar
import CalendarDate
import CalendarValue
import ClockTime
import FixedOffset
import PosixBoundary
import PosixSpan
import Coverage
import PersistenceCalendar
import PersistenceFields
import PersistenceRules
import PersistenceEnvelope

## Internal complete civil snapshot transport. LocalDateTime has no supplied
## precision: native calendar Fraction(6) fields carry its exact clock label,
## including calendar identity, without lowering calendar bounds.
## Flat JSON string arrays begin with strict-v1. Boundary headers contain local,
## occurrence policy, matching offset (empty for other policies), stored position
## and stored offset. Selection headers contain start, end and coverage count,
## followed by canonical half-open endpoint pairs. Complete rule fields follow.
## All coordinates are signed I64 POSIX microseconds, offsets signed I32 seconds.
## Decoding reuses native resolution and rejects any stored-result mismatch.
## Limits: 1024 transitions, 1024 coverage members, 4096 rule metadata bytes,
## 49152 payload bytes and 65536 outer envelope bytes. No partial snapshots.
PersistenceCivil :: { stored : Value, text : Str }.{
	Value : [Boundary(ResolvedBoundary), Selection(ResolvedSelection)]
	Error : [TooLarge, Malformed, Incomplete, UnsupportedPolicy, InvalidLocal(PersistenceCalendar.Error), InvalidContext(PersistenceRules.Error), InvalidInteger, OutOfRange, InvalidSpan([EmptySpan, ReversedBounds]), NonCanonicalCoverage, StoredMismatch, InvalidBoundary([Gap, Ambiguous, OffsetConflict, OutsideValidity, OutOfRange]), InvalidSelection([EmptySelection, ReversedSelection, OutsideValidity, OutOfRange])]
	from_boundary : ResolvedBoundary -> Try(PersistenceCivil, Error)
	from_boundary = |snapshot| {
		rules = ResolvedBoundary.rules(snapshot)
		if !PersistenceRules.fits(rules) {
			return Err(TooLarge)
		}
		policy = match ResolvedBoundary.policy(snapshot) {
			RequireUnique => ["require-unique", ""]
			First => ["first", ""]
			Last => ["last", ""]
			MatchingOffset(offset) => ["matching-offset", FixedOffset.to_seconds(offset).to_str()]
		}
		fields = ["strict-v1", local_text(ResolvedBoundary.source(snapshot))].concat(policy).concat([
			PosixBoundary.to_microseconds(ResolvedBoundary.boundary(snapshot)).to_str(),
			FixedOffset.to_seconds(ResolvedBoundary.offset(snapshot)).to_str(),
		]).concat(PersistenceRules.to_fields(rules))
		finish(Boundary(snapshot), fields, "resolved-boundary", "civil-boundary-snapshot-v1")
	}
	from_selection : ResolvedSelection -> Try(PersistenceCivil, Error)
	from_selection = |snapshot| {
		rules = ResolvedSelection.rules(snapshot)
		coverage = ResolvedSelection.coverage(snapshot)
		if Coverage.member_count(coverage) > 1024 or !PersistenceRules.fits(rules) {
			return Err(TooLarge)
		}
		var fields = ["strict-v1", local_text(ResolvedSelection.start(snapshot)), local_text(ResolvedSelection.end(snapshot)), Coverage.member_count(coverage).to_str()]
		for span in Coverage.to_spans(coverage) {
			fields = fields.append(PosixBoundary.to_microseconds(PosixSpan.start(span)).to_str()).append(PosixBoundary.to_microseconds(PosixSpan.end(span)).to_str())
		}
		finish(Selection(snapshot), fields.concat(PersistenceRules.to_fields(rules)), "resolved-selection", "civil-selection-snapshot-v1")
	}
	value : PersistenceCivil -> Value
	value = |wrapped| wrapped.stored
	to_text : PersistenceCivil -> Str
	to_text = |wrapped| wrapped.text
	parse_boundary : Str -> Try(PersistenceCivil, Error)
	parse_boundary = |text| {
		fields = decode(text)?
		if fields.len() < 19 {
			return Err(Incomplete)
		}
		if at(fields, 0) != "strict-v1" {
			return Err(UnsupportedPolicy)
		}
		local = parse_local(at(fields, 1))?
		policy = match at(fields, 2) {
			"require-unique" => RequireUnique
			"first" => First
			"last" => Last
			"matching-offset" => MatchingOffset(FixedOffset.from_seconds(offset_integer(at(fields, 3))?))
			_ => return Err(UnsupportedPolicy)
		}
		if at(fields, 2) != "matching-offset" and at(fields, 3) != "" {
			return Err(Malformed)
		}
		position = integer(at(fields, 4))?
		offset = offset_integer(at(fields, 5))?
		rules = context(fields.sublist({ start: 6, len: fields.len() - 6 }))?
		snapshot = match ResolvedBoundary.resolve(rules, local, policy) {
			Ok(result) => result
			Err(error) => return Err(InvalidBoundary(error))
		}
		if PosixBoundary.to_microseconds(ResolvedBoundary.boundary(snapshot)) != position or FixedOffset.to_seconds(ResolvedBoundary.offset(snapshot)) != offset {
			return Err(StoredMismatch)
		}
		from_boundary(snapshot)
	}
	parse_selection : Str -> Try(PersistenceCivil, Error)
	parse_selection = |text| {
		fields = decode(text)?
		if fields.len() < 17 {
			return Err(Incomplete)
		}
		if at(fields, 0) != "strict-v1" {
			return Err(UnsupportedPolicy)
		}
		count = integer(at(fields, 3))?
		if count < 0 {
			return Err(InvalidInteger)
		}
		if count > 1024 {
			return Err(TooLarge)
		}
		count_u64 = count.to_u64_wrap()
		header = 4 + count_u64 * 2
		if fields.len() < header + 13 {
			return Err(Incomplete)
		}
		start = parse_local(at(fields, 1))?
		end = parse_local(at(fields, 2))?
		var members = []
		var previous = None
		var index = 0.U64
		while index < count_u64 {
			low = PosixBoundary.from_microseconds(integer(at(fields, 4 + index * 2))?)
			high = PosixBoundary.from_microseconds(integer(at(fields, 5 + index * 2))?)
			span = match PosixSpan.new(low, high) {
				Ok(result) => result
				Err(error) => return Err(InvalidSpan(error))
			}
			match previous {
				Some(last) => if low <= last {
					return Err(NonCanonicalCoverage)
				}
				None => {}
			}
			previous = Some(high)
			members = members.append(span)
			index = index + 1
		}
		expected = match Coverage.from_sorted_spans(members) {
			Ok(result) => result
			Err(_) => return Err(NonCanonicalCoverage)
		}
		rules = context(fields.sublist({ start: header, len: fields.len() - header }))?
		snapshot = match ResolvedSelection.resolve(rules, start, end) {
			Ok(result) => result
			Err(error) => return Err(InvalidSelection(error))
		}
		if ResolvedSelection.coverage(snapshot) != expected {
			return Err(StoredMismatch)
		}
		from_selection(snapshot)
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
			parse_fields = PersistenceFields.parser(encoding, 4113)
			|state| {
				parsed = parse_fields(state)?
				Ok({ value: { values: parsed.value }, rest: parsed.rest })
			}
		}

	}
}

finish : PersistenceCivil.Value, List(Str), Str, Str -> Try(PersistenceCivil, PersistenceCivil.Error)
finish = |stored, fields, kind, profile| {
	text = Json.to_str(fields)
	if text.count_utf8_bytes() > 49152 {
		return Err(TooLarge)
	}
	match PersistenceEnvelope.new({ format: "roc-time", version: "1", kind, profile, axis: "posix-1970", unit: "microsecond", payload: text }) {
		Ok(_) => Ok({ stored, text })
		Err(_) => Err(TooLarge)
	}
}

local_text = |local| {
	date = LocalDateTime.date(local)
	fields = CalendarDate.to_fields(date)
	clock = ClockTime.to_fields(LocalDateTime.clock(local))
	Str.join_with([Calendar.to_name(CalendarDate.calendar(date)), "fraction", fields.year.to_str(), fields.month.to_str(), fields.day.to_str(), clock.hour.to_str(), clock.minute.to_str(), clock.second.to_str(), "6", clock.microsecond.to_str()], ";")
}

parse_local : Str -> Try(LocalDateTime, PersistenceCivil.Error)
parse_local = |text| {
	parsed = match PersistenceCalendar.parse_value(text) {
		Ok(result) => result
		Err(error) => return Err(InvalidLocal(error))
	}
	if CalendarValue.resolution(parsed) != Fraction(6) {
		return Err(Malformed)
	}
	Ok(CalendarValue.start_label(parsed))
}

context : List(Str) -> Try(ZoneRules, PersistenceCivil.Error)
context = |fields| match PersistenceRules.from_fields(fields) {
	Ok(result) => Ok(result)
	Err(TooLarge) => Err(TooLarge)
	Err(TooManyTransitions) => Err(TooLarge)
	Err(error) => Err(InvalidContext(error))
}

integer : Str -> Try(I64, PersistenceCivil.Error)
integer = |text| match PersistenceRules.integer(text) {
	Ok(result) => Ok(result)
	Err(InvalidInteger) => Err(InvalidInteger)
	Err(OutOfRange) => Err(OutOfRange)
	Err(error) => Err(InvalidContext(error))
}

offset_integer : Str -> Try(I32, PersistenceCivil.Error)
offset_integer = |text| match PersistenceRules.offset_integer(text) {
	Ok(result) => Ok(result)
	Err(InvalidInteger) => Err(InvalidInteger)
	Err(OutOfRange) => Err(OutOfRange)
	Err(error) => Err(InvalidContext(error))
}

at = |fields, index| match fields.get(index) {
	Ok(result) => result
	Err(_) => crash "Civil snapshot header length and pair counts validated"
}

decode : Str -> Try(List(Str), PersistenceCivil.Error)
decode = |text| {
	if text.count_utf8_bytes() > 49152 {
		return Err(TooLarge)
	}
	decoded : Try(PersistenceCivil.Fields, [InvalidJson(Str), Encoding([InvalidJson(Str)]), TooManyFields, UnsupportedContainer])
	decoded = Json.parse(text)
	match decoded {
		Ok(result) => Ok(PersistenceCivil.Fields.values(result))
		Err(TooManyFields) => Err(TooLarge)
		Err(_) => Err(Malformed)
	}
}

## Independent finite synthetic timeline: offset +2 before position 0 and zero
## after it. Local .5 is reached at -1.5 and +.5 seconds. This is a timeline
## definition, not an expectation obtained by decoding or formatting a snapshot.
expect {
	rules = test_rules(False)
	local = test_local(500000, Gregorian)
	first = test_boundary(rules, local, First)
	last = test_boundary(rules, local, Last)
	matching = test_boundary(rules, local, MatchingOffset(FixedOffset.from_seconds(2)))
	archived = PersistenceCivil.from_boundary(first)?
	restored = PersistenceCivil.parse_boundary(PersistenceCivil.to_text(archived))?
	first_valid = match PersistenceCivil.value(restored) {
		Boundary(snapshot) => ResolvedBoundary.source(snapshot) == local and ResolvedBoundary.policy(snapshot) == First and PosixBoundary.to_microseconds(ResolvedBoundary.boundary(snapshot)) == -1500000 and FixedOffset.to_seconds(ResolvedBoundary.offset(snapshot)) == 2
		_ => False
	}
	last_archive = PersistenceCivil.from_boundary(last)?
	last_restored = PersistenceCivil.parse_boundary(PersistenceCivil.to_text(last_archive))?
	last_valid = match PersistenceCivil.value(last_restored) {
		Boundary(snapshot) => ResolvedBoundary.policy(snapshot) == Last and PosixBoundary.to_microseconds(ResolvedBoundary.boundary(snapshot)) == 500000
		_ => False
	}
	matching_archive = PersistenceCivil.from_boundary(matching)?
	matching_restored = PersistenceCivil.parse_boundary(PersistenceCivil.to_text(matching_archive))?
	matching_valid = match PersistenceCivil.value(matching_restored) {
		Boundary(snapshot) => ResolvedBoundary.policy(snapshot) == MatchingOffset(FixedOffset.from_seconds(2)) and PosixBoundary.to_microseconds(ResolvedBoundary.boundary(snapshot)) == -1500000
		_ => False
	}
	first_valid and last_valid and matching_valid
}

expect {
	# The same local slice has two separated preimages in the fold, and none
	# in the forward gap. Empty complete coverage must survive as an empty set.
	start = test_local(500000, Julian)
	end = test_local(750000, Julian)
	fold = test_selection(test_rules(False), start, end)
	archive = PersistenceCivil.from_selection(fold)?
	restored = PersistenceCivil.parse_selection(PersistenceCivil.to_text(archive))?
	fold_valid = match PersistenceCivil.value(restored) {
		Selection(snapshot) => {
			coverage = ResolvedSelection.coverage(snapshot)
			ResolvedSelection.start(snapshot) == start and CalendarDate.calendar(LocalDateTime.date(ResolvedSelection.start(snapshot))) == Julian and Coverage.member_count(coverage) == 2 and Coverage.contains(coverage, PosixBoundary.from_microseconds(-1500000)) and !Coverage.contains(coverage, PosixBoundary.from_microseconds(-1250000)) and !Coverage.contains(coverage, PosixBoundary.from_microseconds(0)) and Coverage.contains(coverage, PosixBoundary.from_microseconds(500000)) and !Coverage.contains(coverage, PosixBoundary.from_microseconds(750000))
		}
		_ => False
	}
	gap = test_selection(test_rules(True), start, end)
	gap_archive = PersistenceCivil.from_selection(gap)?
	gap_restored = PersistenceCivil.parse_selection(PersistenceCivil.to_text(gap_archive))?
	gap_valid = match PersistenceCivil.value(gap_restored) {
		Selection(snapshot) => Coverage.member_count(ResolvedSelection.coverage(snapshot)) == 0 and ResolvedSelection.start(snapshot) == start and ResolvedSelection.end(snapshot) == end
		_ => False
	}
	fold_valid and gap_valid
}

expect {
	rules = test_rules(False)
	local = test_local(500000, Gregorian)
	# A stored number alone cannot override the original source and policy.
	wrong_position = Json.to_str(["strict-v1", local_text(local), "first", "", "500000", "2"].concat(PersistenceRules.to_fields(rules)))
	wrong_offset = Json.to_str(["strict-v1", local_text(local), "first", "", "-1500000", "0"].concat(PersistenceRules.to_fields(rules)))
	unique_fold = Json.to_str(["strict-v1", local_text(local), "require-unique", "", "-1500000", "2"].concat(PersistenceRules.to_fields(rules)))
	position_rejected = match PersistenceCivil.parse_boundary(wrong_position) {
		Err(StoredMismatch) => True
		_ => False
	}
	offset_rejected = match PersistenceCivil.parse_boundary(wrong_offset) {
		Err(StoredMismatch) => True
		_ => False
	}
	ambiguous_rejected = match PersistenceCivil.parse_boundary(unique_fold) {
		Err(InvalidBoundary(Ambiguous)) => True
		_ => False
	}
	position_rejected and offset_rejected and ambiguous_rejected
}

expect {
	rules = test_rules(False)
	start = local_text(test_local(500000, Gregorian))
	end = local_text(test_local(750000, Gregorian))
	# Missing a disconnected member is a result mismatch, not partial success.
	missing_member = Json.to_str(["strict-v1", start, end, "1", "500000", "750000"].concat(PersistenceRules.to_fields(rules)))
	touching = Json.to_str(["strict-v1", start, end, "2", "0", "1", "1", "2"].concat(PersistenceRules.to_fields(rules)))
	too_many = Json.to_str(["strict-v1", start, end, "1025"].concat(PersistenceRules.to_fields(rules)))
	missing_rejected = match PersistenceCivil.parse_selection(missing_member) {
		Err(StoredMismatch) => True
		_ => False
	}
	touching_rejected = match PersistenceCivil.parse_selection(touching) {
		Err(NonCanonicalCoverage) => True
		_ => False
	}
	limit_rejected = match PersistenceCivil.parse_selection(too_many) {
		Err(TooLarge) => True
		_ => False
	}
	missing_rejected and touching_rejected and limit_rejected
}

# Synthetic fixtures use only validated public constructors. These literal
# domains are independently known valid; failure is a broken fixture.
test_rules = |gap| {
	validity = test_span(-10000000, 10000000)
	initial = if gap {
		0
	} else {
		2
	}
	following = if gap {
		2
	} else {
		0
	}
	match ZoneRules.new_bounded("Synthetic/CivilArchive", "fixture-v1", validity, FixedOffset.from_seconds(initial), [{ at: PosixBoundary.from_microseconds(0), offset: FixedOffset.from_seconds(following) }], { minimum: 0, maximum: 2 }) {
		Ok(result) => result
		Err(_) => crash "Valid independently defined synthetic rules"
	}
}

test_local = |micros, calendar| match FixedOffset.project(FixedOffset.from_seconds(0), PosixBoundary.from_microseconds(micros), calendar) {
	Ok(result) => result
	Err(_) => crash "Small fixture position in provider range"
}

test_boundary = |rules, local, policy| match ResolvedBoundary.resolve(rules, local, policy) {
	Ok(result) => result
	Err(_) => crash "Known fixture occurrence"
}

test_selection = |rules, start, end| match ResolvedSelection.resolve(rules, start, end) {
	Ok(result) => result
	Err(_) => crash "Known complete fixture selection"
}

test_span = |low, high| match PosixSpan.new(PosixBoundary.from_microseconds(low), PosixBoundary.from_microseconds(high)) {
	Ok(result) => result
	Err(_) => crash "Valid fixed interval"
}
