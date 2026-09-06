import SemanticFact
import CalendarValue
import CalendarDate
import FixedOffset
import PosixBoundary
import PosixSpan
import ZoneRules

## A finite calendar description with explicitly scoped qualifications.
## Uncertain and approximate are independent flags, not numerical tolerances.
## A month qualification does not qualify the year/day or the whole value.
## This is a native description type, not an EDTF parser or reasoning model.
##
## At most one qualification per supplied component and one for the whole value.
## Construction validates and canonicalizes at most eight entries; input order
## has no semantic meaning. Whole and component qualifications may coexist and
## are retained independently, without inferring redundancy or contradiction.
QualifiedCalendarValue :: { value : CalendarValue, qualifications : List(Qualification) }.{
	Scope : [Whole, Year, Month, Day, Hour, Minute, Second, Fraction]
	Qualifier : [Uncertain, Approximate, UncertainApproximate]
	Qualification : { scope : Scope, qualifier : Qualifier }
	new : CalendarValue, List(Qualification) -> Try(QualifiedCalendarValue, [TooManyQualifications, DuplicateScope(Scope), UnsuppliedComponent(Scope), ..])
	new = |value, qualifications| {
		if qualifications.len() > 8 {
			return Err(TooManyQualifications)
		}
		supplied = match CalendarValue.resolution(value) {
			Year => 1.U8
			Month => 2
			Day => 3
			Hour => 4
			Minute => 5
			Second => 6
			Fraction(_) => 7
		}
		var seen = []
		for item in qualifications {
			if scope_rank(item.scope) > supplied {
				return Err(UnsuppliedComponent(item.scope))
			}
			if seen.contains(item.scope) {
				return Err(DuplicateScope(item.scope))
			}
			seen = seen.append(item.scope)
		}
		canonical = qualifications.sort_with(
			|a, b| {
				left = scope_rank(a.scope)
				right = scope_rank(b.scope)
				if left < right {
					Before
				} else if left > right {
					After
				} else {
					Same
				}
			},
		)
		Ok({ value, qualifications: canonical })
	}

	## The named value alone is descriptive evidence, not an interpretation of
	## its qualifiers. Extracting it does not establish an admissible tolerance.
	described_value : QualifiedCalendarValue -> CalendarValue
	described_value = |description| description.value
	qualifications : QualifiedCalendarValue -> List(Qualification)
	qualifications = |description| description.qualifications

	## Only an unqualified description has an unconditional certain selection.
	## Qualified descriptions require an explicit admissible model; CalendarEvidence
	## provides finite-alternative point queries. NeedsModel is checked here before
	## any zone work or range lowering.
	selection_cursor : QualifiedCalendarValue, ZoneRules -> Try(ZoneRules.SelectionCursor, [NeedsModel, OutOfRange, EmptySelection, ReversedSelection, OutsideValidity, ..])
	selection_cursor = |description, rules| {
		if !description.qualifications.is_empty() {
			return Err(NeedsModel)
		}
		CalendarValue.selection_cursor(description.value, rules)
	}

	is_eq : QualifiedCalendarValue, QualifiedCalendarValue -> Bool
	is_eq = |a, b| a.value == b.value and a.qualifications == b.qualifications
	to_hash : QualifiedCalendarValue, Hasher -> Hasher
	to_hash = |description, hasher| {
		var state = description.value.to_hash(hasher)
		for item in description.qualifications {
			code = match item.qualifier {
				Uncertain => 0.U8
				Approximate => 1
				UncertainApproximate => 2
			}
			state = code.to_hash(scope_rank(item.scope).to_hash(state))
		}
		description.qualifications.len().to_hash(state)
	}

	## Summary, zone requirement, optional model requirement, then scoped facts.
	## Indexing does not enumerate qualifications or interpret their meaning.
	fact_count : QualifiedCalendarValue -> U64
	fact_count = |description| if description.qualifications.is_empty() {
		2
	} else {
		3 + description.qualifications.len()
	}
	fact_at : QualifiedCalendarValue, U64 -> [End, Item(SemanticFact)]
	fact_at = |description, index| {
		if index == 0 {
			match CalendarValue.fact_at(description.value, 0) {
				Item(fact) => match SemanticFact.kind(fact) {
					CalendarDescription(data) => return Item(SemanticFact.new(CalendarDescription({ ..data, kind: QualifiedCalendarValue, qualification_count: description.qualifications.len() })))
					_ => crash "CalendarValue index zero is its calendar summary"
				}
				End => crash "CalendarValue index zero exists"
			}
		}
		if index == 1 {
			return Item(SemanticFact.new(Requirement(ZoneContext)))
		}
		if description.qualifications.is_empty() {
			return End
		}
		if index == 2 {
			return Item(SemanticFact.new(Requirement(UncertaintyModel)))
		}
		match description.qualifications.get(index - 3) {
			Ok(q) => Item(SemanticFact.new(Qualification(q)))
			Err(_) => End
		}
	}
	to_inspect : QualifiedCalendarValue -> Str
	to_inspect = |description| match fact_at(description, 0) {
		Item(fact) => SemanticFact.summary(fact)
		End => crash "QualifiedCalendarValue always has a summary at index zero"
	}
}

scope_rank : QualifiedCalendarValue.Scope -> U8
scope_rank = |scope| match scope {
	Whole => 0
	Year => 1
	Month => 2
	Day => 3
	Hour => 4
	Minute => 5
	Second => 6
	Fraction => 7
}

expect {
	year = CalendarValue.year(Gregorian, 2004)?
	QualifiedCalendarValue.new(year, [{ scope: Month, qualifier: Approximate }]) == Err(UnsuppliedComponent(Month)) and
		QualifiedCalendarValue.new(year, [{ scope: Year, qualifier: Uncertain }, { scope: Year, qualifier: Approximate }]) == Err(DuplicateScope(Year)) and
			QualifiedCalendarValue.new(year, List.repeat({ scope: Year, qualifier: Uncertain }, 9)) == Err(TooManyQualifications)
}
expect {
	month = CalendarValue.month(Gregorian, 2004, 6)?
	a = QualifiedCalendarValue.new(month, [{ scope: Whole, qualifier: Uncertain }, { scope: Month, qualifier: Approximate }])?
	b = QualifiedCalendarValue.new(month, [{ scope: Month, qualifier: Approximate }, { scope: Whole, qualifier: Uncertain }])?
	c = QualifiedCalendarValue.new(month, [{ scope: Whole, qualifier: UncertainApproximate }])?
	a == b and a != c and QualifiedCalendarValue.described_value(a) == month
}

expect {
	# EDTF's individual-component form, 2004-~06-11, constructed natively.
	# The day remains supplied and unqualified; this does not assert a tolerance.
	date = CalendarDate.from_fields(Gregorian, { year: 2004, month: 6, day: 11 })?
	value = CalendarValue.day(date)
	month_only = QualifiedCalendarValue.new(value, [{ scope: Month, qualifier: Approximate }])?
	whole = QualifiedCalendarValue.new(value, [{ scope: Whole, qualifier: Approximate }])?
	validity = PosixSpan.new(PosixBoundary.from_microseconds(I64.lowest), PosixBoundary.from_microseconds(I64.highest))?
	rules = ZoneRules.new_bounded("UTC", "v1", validity, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 })?
	denied = match QualifiedCalendarValue.selection_cursor(month_only, rules) {
		Err(NeedsModel) => True
		_ => False
	}
	month_only != whole and denied and
		QualifiedCalendarValue.qualifications(month_only) == [{ scope: Month, qualifier: Approximate }] and
			QualifiedCalendarValue.described_value(month_only) == value
}

expect {
	value = CalendarValue.year(Gregorian, 1984)?
	plain = QualifiedCalendarValue.new(value, [])?
	qualified = QualifiedCalendarValue.new(value, [{ scope: Whole, qualifier: Uncertain }])?
	QualifiedCalendarValue.fact_count(plain) == 2 and QualifiedCalendarValue.fact_at(plain, 2) == End and
		QualifiedCalendarValue.fact_count(qualified) == 4 and
			QualifiedCalendarValue.fact_at(qualified, 2) == Item(SemanticFact.new(Requirement(UncertaintyModel))) and
				QualifiedCalendarValue.fact_at(qualified, 3) == Item(SemanticFact.new(Qualification({ scope: Whole, qualifier: Uncertain }))) and
					QualifiedCalendarValue.fact_at(qualified, U64.highest) == End
}
