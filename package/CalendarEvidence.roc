import CalendarValue
import QualifiedCalendarValue
import CalendarDate
import ClockTime
import LocalDateTime
import ZoneRules
import FixedOffset
import PosixBoundary
import PosixSpan

## Explicit finite admissible values for a qualified calendar description.
## The caller supplies alternatives; no tolerance, distribution or probability
## is inferred. Exactly one alternative is the actual civil selection. Each
## selection retains its full preimage, including disconnected fold components.
## This native model is not an EDTF parser or general interval-reasoning engine.
##
## All alternatives retain the description's calendar and resolution. Components
## without a qualification must equal the described value unless Whole is
## qualified. Both uncertain and approximate components may vary only because
## the caller supplied this model. A model may include the described value.
##
## At most 4096 input alternatives, before deduplication. Construction validates
## fields and exclusive civil bounds once, then sorts/deduplicates in O(n log n), without zone interpretation or
## enumeration. Canonical order is local position, not resolved timeline order.
CalendarEvidence :: { description : QualifiedCalendarValue, alternatives : List({ value : CalendarValue, end : LocalDateTime }) }.{
	Truth : [Definite, Possible, Impossible]
	profile : Str
	profile = "finite-calendar-alternatives-v1"
	new : QualifiedCalendarValue, List(CalendarValue) -> Try(CalendarEvidence, [InconsistentEvidence, TooManyAlternatives, CalendarMismatch(U64), ResolutionMismatch(U64), UnqualifiedComponent({ index : U64, scope : QualifiedCalendarValue.Scope }), CandidateOutOfRange(U64), ..])
	new = |description, alternatives| {
		if alternatives.is_empty() {
			return Err(InconsistentEvidence)
		}
		if alternatives.len() > 4096 {
			return Err(TooManyAlternatives)
		}
		base = QualifiedCalendarValue.described_value(description)
		allowed = QualifiedCalendarValue.qualifications(description).map(|item| item.scope)
		var $validated = []
		var $index = 0.U64
		for candidate in alternatives {
			if CalendarDate.calendar(LocalDateTime.date(CalendarValue.start_label(base))) != CalendarDate.calendar(LocalDateTime.date(CalendarValue.start_label(candidate))) {
				return Err(CalendarMismatch($index))
			}
			if CalendarValue.resolution(base) != CalendarValue.resolution(candidate) {
				return Err(ResolutionMismatch($index))
			}
			if !allowed.contains(Whole) {
				base_fields = components(base)
				fields = components(candidate)
				for pair in [
					{ scope: Year, changed: base_fields.date.year != fields.date.year },
					{ scope: Month, changed: base_fields.date.month != fields.date.month },
					{ scope: Day, changed: base_fields.date.day != fields.date.day },
					{ scope: Hour, changed: base_fields.clock.hour != fields.clock.hour },
					{ scope: Minute, changed: base_fields.clock.minute != fields.clock.minute },
					{ scope: Second, changed: base_fields.clock.second != fields.clock.second },
					{ scope: Fraction, changed: base_fields.clock.microsecond != fields.clock.microsecond },
				] {
					if pair.changed and !allowed.contains(pair.scope) {
						return Err(UnqualifiedComponent({ index: $index, scope: pair.scope }))
					}
				}
			}
			bounds = match CalendarValue.local_bounds(candidate) {
				Ok(value) => value
				Err(OutOfRange) => return Err(CandidateOutOfRange($index))
			}
			$validated = $validated.append({ value: candidate, end: bounds.end })
			$index = $index + 1
		}
		sorted = $validated.sort_with(
			|a, b| match LocalDateTime.compare_position(CalendarValue.start_label(a.value), CalendarValue.start_label(b.value)) {
				LT => Before
				EQ => Same
				GT => After
			},
		)
		var $canonical = []
		for candidate in sorted {
			previous = $canonical.last()
			if previous != Ok(candidate) {
				$canonical = $canonical.append(candidate)
			}
		}
		Ok({ description, alternatives: $canonical })
	}
	description : CalendarEvidence -> QualifiedCalendarValue
	description = |evidence| evidence.description

	## Materialize the canonical alternatives as a caller-owned list, O(n).
	alternatives : CalendarEvidence -> List(CalendarValue)
	alternatives = |evidence| evidence.alternatives.map(|item| item.value)

	## Is this one POSIX instant inside the unknown actual selection? Only the
	## point must lie within the rules' validity; no claim about full preimages
	## outside that validity is made. Projection is O(log transition_count).
	## Each subsequent work unit checks one alternative's civil bounds in O(1).
	## Rules, point and model are immutable across resumptions. No coverage list
	## is built. Construction rejects an unrepresentable exclusive civil bound
	## before any query can stop early on sufficient witnesses.
	query : CalendarEvidence, ZoneRules, PosixBoundary -> Try(Query, [OutsideValidity, OutOfRange, ..])
	query = |evidence, rules, point| {
		offset = ZoneRules.offset_at(rules, point)?
		calendar = CalendarDate.calendar(LocalDateTime.date(CalendarValue.start_label(QualifiedCalendarValue.described_value(evidence.description))))
		local = FixedOffset.project(offset, point, calendar)?
		Ok({ evidence, rules, point, local, index: 0, yes: Bool.False, no: Bool.False })
	}
	Batch : { examined : U64, status : [Complete(Truth), Limited(Query)] }
	Query :: { evidence : CalendarEvidence, rules : ZoneRules, point : PosixBoundary, local : LocalDateTime, index : U64, yes : Bool, no : Bool }.{
		collect : Query, { max_alternatives : U64 } -> Batch
		collect = |initial, limits| {
			var $state = initial
			var $examined = 0.U64
			while Bool.True {
				if $state.yes and $state.no {
					return { examined: $examined, status: Complete(Possible) }
				}
				if $state.index == $state.evidence.alternatives.len() {
					truth = if $state.yes {
						Definite
					} else {
						Impossible
					}
					return { examined: $examined, status: Complete(truth) }
				}
				if $examined == limits.max_alternatives {
					return { examined: $examined, status: Limited($state) }
				}
				candidate = match $state.evidence.alternatives.get($state.index) {
					Ok(value) => value
					Err(_) => crash "Validated evidence cursor index"
				}
				bounds = { start: CalendarValue.start_label(candidate.value), end: candidate.end }
				inside = LocalDateTime.compare_position(bounds.start, $state.local) != GT and LocalDateTime.compare_position($state.local, bounds.end) == LT
				$state = { ..$state, index: $state.index + 1, yes: $state.yes or inside, no: $state.no or !inside }
				$examined = $examined + 1
			}
			crash "Evidence loop returns an outcome"
		}
		to_inspect : Query -> Str
		to_inspect = |state| "CalendarEvidence.Query(examined=${state.index.to_str()}, point=${Str.inspect(state.point)})"
	}
	is_eq : CalendarEvidence, CalendarEvidence -> Bool
	is_eq = |a, b| a.description == b.description and a.alternatives == b.alternatives
	to_hash : CalendarEvidence, Hasher -> Hasher
	to_hash = |evidence, hasher| {
		var $state = evidence.description.to_hash(hasher)
		for value in evidence.alternatives {
			$state = value.value.to_hash($state)
		}
		evidence.alternatives.len().to_hash($state)
	}
	to_inspect : CalendarEvidence -> Str
	to_inspect = |evidence| "CalendarEvidence(alternatives=${evidence.alternatives.len().to_str()}, description=${Str.inspect(evidence.description)})"
}

components = |value| {
	start = CalendarValue.start_label(value)
	{ date: CalendarDate.to_fields(LocalDateTime.date(start)), clock: ClockTime.to_fields(LocalDateTime.clock(start)) }
}

expect {
	base = CalendarValue.month(Gregorian, 2004, 6)?
	description = QualifiedCalendarValue.new(base, [{ scope: Month, qualifier: Approximate }])?
	july = CalendarValue.month(Gregorian, 2004, 7)?
	a = CalendarEvidence.new(description, [base, july, base])?
	b = CalendarEvidence.new(description, [july, base])?
	a == b and CalendarEvidence.alternatives(a) == [base, july] and
		CalendarEvidence.new(description, []) == Err(InconsistentEvidence) and
			CalendarEvidence.new(description, List.repeat(base, 4097)) == Err(TooManyAlternatives) and
				CalendarEvidence.new(description, [CalendarValue.month(Gregorian, 2005, 6)?]) == Err(UnqualifiedComponent({ index: 0, scope: Year })) and
					CalendarEvidence.new(description, [CalendarValue.month(Julian, 2004, 6)?]) == Err(CalendarMismatch(0)) and
						CalendarEvidence.new(description, [CalendarValue.year(Gregorian, 2004)?]) == Err(ResolutionMismatch(0))
}
expect {
	base = CalendarValue.year(Gregorian, 2000)?
	description = QualifiedCalendarValue.new(base, [{ scope: Whole, qualifier: Uncertain }])?
	# The third candidate cannot be hidden by early Possible witnesses.
	CalendarEvidence.new(description, [base, CalendarValue.year(Gregorian, 2001)?, CalendarValue.year(Gregorian, 2147483647)?]) == Err(CandidateOutOfRange(2))
}

expect {
	# Independent epoch fixtures: one of Jan 1/Jan 2 is not their certain union.
	first = CalendarValue.day(CalendarDate.from_fields(Gregorian, { year: 1970, month: 1, day: 1 })?)
	second = CalendarValue.day(CalendarDate.from_fields(Gregorian, { year: 1970, month: 1, day: 2 })?)
	description = QualifiedCalendarValue.new(first, [{ scope: Day, qualifier: Uncertain }])?
	alternatives = CalendarEvidence.new(description, [first, second])?
	singleton = CalendarEvidence.new(description, [first])?
	rules = test_rules()?
	a = CalendarEvidence.Query.collect(CalendarEvidence.query(alternatives, rules, PosixBoundary.from_microseconds(0))?, { max_alternatives: 2 })
	b = CalendarEvidence.Query.collect(CalendarEvidence.query(alternatives, rules, PosixBoundary.from_microseconds(172800000000))?, { max_alternatives: 2 })
	c = CalendarEvidence.Query.collect(CalendarEvidence.query(singleton, rules, PosixBoundary.from_microseconds(0))?, { max_alternatives: 1 })
	match (a.status, b.status, c.status) {
		(Complete(Possible), Complete(Impossible), Complete(Definite)) => True
		_ => False
	}
}
expect {
	value = CalendarValue.year(Gregorian, 1970)?
	description = QualifiedCalendarValue.new(value, [])?
	evidence = CalendarEvidence.new(description, [value])?
	match CalendarEvidence.query(evidence, test_rules()?, PosixBoundary.from_microseconds(I64.highest)) {
		Err(OutsideValidity) => True
		_ => False
	}
}
test_rules = || {
	validity = PosixSpan.new(PosixBoundary.from_microseconds(I64.lowest), PosixBoundary.from_microseconds(I64.highest))?
	ZoneRules.new_bounded("UTC", "v1", validity, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 })
}
