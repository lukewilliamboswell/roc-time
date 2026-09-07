import fuzz.Fuzz
import time.LocalDateTime
import time.Explanation
import time.SemanticFact
import time.CalendarValue
import time.IntervalEvidence
import time.CalendarEvidence
import time.QualifiedCalendarValue
import time.CalendarDate
import time.FixedOffset
import time.PosixBoundary
import time.PosixSpan
import time.Coverage
import time.ZoneRules

# R02/R07/R13–R14: bounded decimal grids, full-day carries and synthetic preimages.
# The oracle uses integer grid widths and two explicitly known offset segments;
# it neither calls CalendarValue.local_bounds nor the resolver to form expectations.
DescriptionCase := { number : U64, digits : U8, gap : Bool }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(DescriptionCase)
	generator_for = |_| { number: Fuzz.u64_in(0, 86399999999), digits: Fuzz.u8_in(1, 6), gap: Fuzz.map(Fuzz.u8_in(0, 1), |n| n == 1) }.Fuzz
	check : DescriptionCase -> Fuzz.Outcome
	check = |input| {
		date = match epoch_date(input.digits) {
			Ok(value) => value
			Err(_) => crash "Valid epoch date"
		}
		number = input.number.to_i64_wrap()
		h = (number // 3600000000).to_u8_wrap()
		m = I64.mod_by(number // 60000000, 60).to_u8_wrap()
		s = I64.mod_by(number // 1000000, 60).to_u8_wrap()
		var $width = 1000000.I64
		var $index = 0.U8
		while $index < input.digits {
			$width = $width // 10
			$index = $index + 1
		}
		fraction = (I64.mod_by(number, 1000000) // $width).to_u32_wrap()
		value = match CalendarValue.fractional_second(date, { hour: h, minute: m, second: s }, { value: fraction, digits: input.digits }) {
			Ok(found) => found
			Err(_) => crash "Valid decimal grid rejected"
		}
		check_calendar_description(input, h, m, s, fraction)
		start = (number // $width) * $width
		check_bounds(value, start, $width)
		hour = match CalendarValue.hour(date, h) {
			Ok(found) => found
			Err(_) => crash "Valid hour"
		}
		minute = match CalendarValue.minute(date, h, m) {
			Ok(found) => found
			Err(_) => crash "Valid minute"
		}
		second = match CalendarValue.second(date, h, m, s) {
			Ok(found) => found
			Err(_) => crash "Valid second"
		}
		check_bounds(hour, (number // 3600000000) * 3600000000, 3600000000)
		check_bounds(minute, (number // 60000000) * 60000000, 60000000)
		check_bounds(second, (number // 1000000) * 1000000, 1000000)
		check_bounds(CalendarValue.day(date), 0, 86400000000)
		if CalendarValue.resolution(value) != Fraction(input.digits) or CalendarValue.resolution(second) != Second {
			crash "Description lost resolution"
		}
		# Two-second jump around the entire decimal cell. A fold has exactly
		# two disjoint copies; reversing the offsets makes the cell absent.
		initial = if input.gap {
			0.I32
		} else {
			2.I32
		}
		after = 2 - initial
		rules = match ZoneRules.new_bounded("Synthetic/Description", "v1", span(start - 4000000, start + 4000000), FixedOffset.from_seconds(initial), [{ at: point(start - 1000000), offset: FixedOffset.from_seconds(after) }], { minimum: 0, maximum: 2 }) {
			Ok(found) => found
			Err(_) => crash "Valid synthetic rules"
		}
		check_qualifications(value, minute, rules, input.number)
		check_group_evidence(input.number)
		check_evidence(date, value, rules, input, start, $width, after)
		check_intervals(input)
		plain = qualified(value, [])
		cursor = match QualifiedCalendarValue.selection_cursor(plain, rules) {
			Ok(found) => found
			Err(_) => crash "Valid description selection"
		}
		first = match ZoneRules.SelectionCursor.collect(cursor, { max_segments: 0, max_members: 2 }) {
			Ok(found) => found
			Err(_) => crash "Zero-work selection"
		}
		var $resumed = match first.status {
			Limited(progress) => progress.cursor
			Complete(_) => crash "Zero budget must remain incomplete"
		}
		var $result = Coverage.empty
		var $done = Bool.False
		var $calls = 0.U64
		while $calls < 4 and !$done {
			batch = match ZoneRules.SelectionCursor.collect($resumed, { max_segments: 1, max_members: 2 }) {
				Ok(found) => found
				Err(_) => crash "Bounded selection failed"
			}
			match batch.status {
				Complete(coverage) => {
					$result = coverage
					$done = Bool.True
				}
				Limited(progress) => {
					$resumed = progress.cursor
				}
			}
			$calls = $calls + 1
		}
		expected = if input.gap {
			Coverage.empty
		} else {
			Coverage.from_spans([span(start - 2000000, start - 2000000 + $width), span(start, start + $width)])
		}
		if !$done or $result != expected {
			crash "Calendar selection differs from independent two-segment preimage"
		}
		Fuzz.Outcome.Keep
	}
}

check_bounds = |value, start, width| {
	bounds = match CalendarValue.local_bounds(value) {
		Ok(found) => found
		Err(_) => crash "Valid civil bounds"
	}
	zero = FixedOffset.from_seconds(0)
	if FixedOffset.resolve(zero, bounds.start) != Ok(point(start)) or FixedOffset.resolve(zero, bounds.end) != Ok(point(start + width)) {
		crash "Calendar description differs from decimal grid"
	}
}

point = |number| PosixBoundary.from_microseconds(number)

span = |start, end| match PosixSpan.new(point(start), point(end)) {
	Ok(value) => value
	Err(_) => crash "Nonempty oracle span"
}

epoch_date = |_digits| CalendarDate.from_fields(Gregorian, { year: 1970, month: 1, day: 1 })

# Independent set model: qualifier order is irrelevant, but scopes and flags
# remain distinct. Every listed fractional component exists; seconds were not
# supplied in the minute value. No numeric tolerance follows from any flag.
check_qualifications = |value, minute, rules, number| {
	scopes : List(QualifiedCalendarValue.Scope)
	scopes = [Whole, Year, Month, Day, Hour, Minute, Second, Fraction, YearMonth]
	var $forward = []
	var $backward = []
	var $bits = number
	for scope in scopes {
		flag = match $bits % 3 {
			0 => Uncertain
			1 => Approximate
			_ => UncertainApproximate
		}
		if $bits % 2 == 0 {
			item = { scope, qualifier: flag }
			$forward = $forward.append(item)
			$backward = [item].concat($backward)
		}
		$bits = $bits // 2
	}
	a = qualified(value, $forward)
	b = qualified(value, $backward)
	# Retain both input lists and a slice while canonicalization may sort them.
	sliced = [{ scope: Whole, qualifier: Uncertain }].concat($backward).drop_first(1)
	c = qualified(value, sliced)
	if a != b or a != c or QualifiedCalendarValue.qualifications(a).len() != $forward.len() or QualifiedCalendarValue.described_value(a) != value {
		crash "Qualification set changed under ordering or sharing"
	}
	for item in $forward {
		if !QualifiedCalendarValue.qualifications(a).contains(item) {
			crash "Qualification fact lost"
		}
	}
	if !$forward.is_empty() {
		match QualifiedCalendarValue.selection_cursor(a, rules) {
			Err(NeedsModel) => {}
			_ => crash "Qualifier invented a certain selection"
		}
	}
	for scope in scopes {
		result = QualifiedCalendarValue.new(minute, [{ scope, qualifier: Approximate }])
		if scope == Second or scope == Fraction {
			if result != Err(UnsuppliedComponent(scope)) {
				crash "Qualifier applied to an omitted component"
			}
		} else {
			match result {
				Ok(_) => {}
				Err(_) => crash "Supplied component rejected"
			}
		}
		if QualifiedCalendarValue.new(value, [{ scope, qualifier: Approximate }, { scope, qualifier: Uncertain }]) != Err(DuplicateScope(scope)) {
			crash "Duplicate qualification scope accepted"
		}
	}
}

# Independent three-bit field-change model: a year-month group permits exactly
# the year and month coordinates to vary; the supplied day remains fixed.
# Days 11/12 are valid in every generated Gregorian month, including February.
check_group_evidence = |number| {
	year = 2000 + (number % 100).to_i64_wrap()
	month = (1.U64 + number % 11).to_u8_wrap()
	base = group_day(year, month, 11)
	group = qualified(base, [{ scope: YearMonth, qualifier: Approximate }])
	whole = qualified(base, [{ scope: Whole, qualifier: Approximate }])
	individual = qualified(base, [{ scope: Month, qualifier: Approximate }])
	var $mask = 0.U8
	while $mask < 8 {
		year_changed = $mask % 2 == 1
		month_changed = ($mask // 2) % 2 == 1
		day_changed = $mask >= 4
		candidate = group_day(
			year + (
				if year_changed {
					1
				} else {
					0
				}
			),
			month + (
				if month_changed {
					1
				} else {
					0
				}
			),
			if day_changed {
				12
			} else {
				11
			},
		)
		result = CalendarEvidence.new(group, [candidate])
		if day_changed {
			if result != Err(UnqualifiedComponent({ index: 0, scope: Day })) {
				crash "Group changed unqualified day"
			}
		} else {
			match result {
				Ok(_) => {}
				Err(_) => crash "Group rejected supplied year/month alternative"
			}
		}
		match CalendarEvidence.new(whole, [candidate]) {
			Ok(_) => {}
			Err(_) => crash "Whole rejected supplied alternative"
		}
		if year_changed {
			if CalendarEvidence.new(individual, [candidate]) != Err(UnqualifiedComponent({ index: 0, scope: Year })) {
				crash "Individual month changed year"
			}
		}
		$mask = $mask + 1
	}
}

group_day = |year, month, day| match CalendarDate.from_fields(Gregorian, { year, month, day }) {
	Ok(date) => CalendarValue.day(date)
	Err(_) => crash "Generated interior day is valid"
}

qualified = |value, items| match QualifiedCalendarValue.new(value, items) {
	Ok(found) => found
	Err(_) => crash "Valid qualifications rejected"
}

# R13: finite-model oracle. Candidate cells are formed independently from
# decimal coordinate arithmetic. For each point, count true model rows directly
# and compare all/some/none with bounded, resumed public evidence queries.
check_evidence = |date, value, rules, input, start, width, offset| {
	description = qualified(value, [{ scope: Second, qualifier: UncertainApproximate }])
	var $alternatives = []
	var $starts = []
	var $n = 0.I64
	minute_start = (start // 60000000) * 60000000
	original_second = (start - minute_start) // 1000000
	fraction = I64.mod_by(start, 1000000)
	while $n < 4 {
		chosen_second = I64.mod_by(original_second + $n, 60)
		if (input.number % 3 == 0 and $n == 0) or (input.number % 3 != 0 and (input.number % 2 == 0 or $n != 0)) {
			chosen = minute_start + chosen_second * 1000000 + fraction
			h = (chosen // 3600000000).to_u8_wrap()
			m = I64.mod_by(chosen // 60000000, 60).to_u8_wrap()
			candidate = match CalendarValue.fractional_second(date, { hour: h, minute: m, second: chosen_second.to_u8_wrap() }, { value: (fraction // width).to_u32_wrap(), digits: input.digits }) {
				Ok(found) => found
				Err(_) => crash "Valid evidence candidate"
			}
			$alternatives = $alternatives.append(candidate)
			$starts = $starts.append(chosen)
		}
		$n = $n + 1
	}
	model = match CalendarEvidence.new(description, $alternatives.concat($alternatives)) {
		Ok(found) => found
		Err(_) => crash "Valid finite model rejected"
	}
	if CalendarEvidence.alternatives(model).len() != $alternatives.len() {
		crash "Duplicate model rows retained"
	}
	# Both tested points occur after the synthetic transition. Exact lower and
	# upper cell endpoints exercise half-open membership without using bounds.
	for coordinate in [start, start + width] {
		local_point = coordinate + offset.to_i64() * 1000000
		var $yes = 0.U64
		for lower in $starts {
			if lower <= local_point and local_point < lower + width {
				$yes = $yes + 1
			}
		}
		expected = if $yes == 0 {
			Impossible
		} else if $yes == $starts.len() {
			Definite
		} else {
			Possible
		}
		query = match CalendarEvidence.query(model, rules, point(coordinate)) {
			Ok(found) => found
			Err(_) => crash "Valid model point rejected"
		}
		zero = CalendarEvidence.Query.collect(query, { max_alternatives: 0 })
		var $cursor = match zero.status {
			Limited(found) => found
			Complete(_) => crash "Zero work claimed complete evidence"
		}
		var $finished = Bool.False
		var $calls = 0.U64
		while $calls < 4 and !$finished {
			batch = CalendarEvidence.Query.collect($cursor, { max_alternatives: 1 })
			if batch.examined > 1 {
				crash "Evidence work budget exceeded"
			}
			match batch.status {
				Complete(truth) => {
					if truth != expected {
						crash "Finite reasoning differs from model enumeration"
					}
					$finished = Bool.True
				}
				Limited(next) => {
					$cursor = next
				}
			}
			$calls = $calls + 1
		}
		whole = CalendarEvidence.Query.collect(query, { max_alternatives: 4 })
		match whole.status {
			Complete(truth) => if !$finished or truth != expected {
				crash "Evidence resumption changed truth"
			}
			Limited(_) => crash "Sufficient model work incomplete"
		}
	}
}

# R01/R13: finite endpoint evidence; no zone interpretation is involved. Enumerate
# every valid start/end pair in a six-point model, rather than using extrema or
# coverage algebra as the oracle. Bits select arbitrary subsets (including empty
# ones); signed extremes and adjacent central endpoints are always in the pool.
# The retained lists and padded slices exercise normalization with shared storage.
check_intervals = |input| {
	center = if input.gap {
		input.number.to_i64_wrap()
	} else {
		-input.number.to_i64_wrap()
	}
	points = [I64.lowest, center - 1, center, center + 1, center + 2, I64.highest]
	var $starts = []
	var $ends = []
	var $pairs = []
	var $paired_spans = []
	var $bits = input.number
	for coordinate in points {
		if $bits % 2 == 1 {
			$starts = $starts.append(coordinate)
		}
		if ($bits // 2) % 2 == 1 {
			$ends = $ends.append(coordinate)
		}
		$bits = $bits // 4
	}
	$bits = input.number
	for start in points {
		for end in points {
			if start < end {
				if $bits % 2 == 1 {
					$pairs = $pairs.append({ start, end })
					$paired_spans = $paired_spans.append(span(start, end))
				}
				$bits = $bits // 2
			}
		}
	}
	paired = IntervalEvidence.paired($paired_spans)
	if $pairs.is_empty() {
		if paired != Err(InconsistentEvidence) {
			crash "Empty paired evidence succeeded"
		}
	} else {
		evidence = match paired {
			Ok(found) => found
			Err(_) => crash "Valid paired evidence rejected"
		}
		sliced = [span(center - 1, center)].concat($paired_spans.concat($paired_spans)).drop_first(1)
		if IntervalEvidence.paired(sliced) != Ok(evidence) {
			crash "Shared paired normalization changed declaration"
		}
		check_interval_truth(evidence, $pairs, points)
	}
	var $admissible = []
	for start in $starts {
		for end in $ends {
			if start < end {
				$admissible = $admissible.append({ start, end })
			}
		}
	}
	start_points = $starts.map(point)
	end_points = $ends.map(point)
	independent = IntervalEvidence.independent({ starts: start_points, ends: end_points })
	if $admissible.is_empty() {
		if independent != Err(InconsistentEvidence) {
			crash "Inconsistent endpoint evidence succeeded"
		}
	} else {
		evidence = match independent {
			Ok(found) => found
			Err(_) => crash "Admissible endpoint evidence rejected"
		}
		sliced_starts = [point(center)].concat(start_points.concat(start_points)).drop_first(1)
		sliced_ends = [point(center)].concat(end_points.concat(end_points)).drop_first(1)
		if IntervalEvidence.independent({ starts: sliced_starts, ends: sliced_ends }) != Ok(evidence) {
			crash "Shared endpoint normalization changed declaration"
		}
		check_interval_truth(evidence, $admissible, points)
	}
}

check_interval_truth = |evidence, intervals, points| {
	for coordinate in points {
		var $yes = 0.U64
		for interval in intervals {
			if interval.start <= coordinate and coordinate < interval.end {
				$yes = $yes + 1
			}
		}
		expected = if $yes == 0 {
			Impossible
		} else if $yes == intervals.len() {
			Definite
		} else {
			Possible
		}
		if IntervalEvidence.contains(evidence, point(coordinate)) != expected {
			crash "Interval truth differs from exhaustive admissible model"
		}
		if Coverage.contains(IntervalEvidence.possible_coverage(evidence), point(coordinate)) != ($yes > 0) or
			Coverage.contains(IntervalEvidence.definite_coverage(evidence), point(coordinate)) != ($yes == intervals.len()) {
			crash "Interval coverage projections differ from quantified membership"
		}
	}
}

# R02/R13/R14: native calendar identity, provider limits and independently
# ordered qualification scopes remain observable without coordinate lowering.
check_calendar_description = |input, h, m, s, fraction| {
	for calendar in [Gregorian, Julian] {
		date = CalendarDate.from_fields(calendar, { year: 1970, month: 1, day: 1 }) ?? crash "valid description date"
		fractional = CalendarValue.fractional_second(date, { hour: h, minute: m, second: s }, { digits: input.digits, value: fraction }) ?? crash "valid fractional description"
		check_explanation(fractional, calendar, input, h, m, s, fraction)
		for limit in [-2147483648.I64, 2147483647] {
			value = CalendarValue.year(calendar, limit) ?? crash "provider year limit rejected"
			label = LocalDateTime.date(CalendarValue.start_label(value))
			if CalendarDate.calendar(label) != calendar or CalendarDate.to_fields(label).year != limit or CalendarValue.resolution(value) != Year {
				crash "native provider limit lost identity or resolution"
			}
		}
		scopes : List(QualifiedCalendarValue.Scope)
		scopes = [Whole, Year, Month, Day, Hour, Minute, Second, Fraction]
		var $items = []
		var $expected = []
		var $bits = input.number
		for scope in scopes {
			qualifier = match $bits % 3 {
				0 => Uncertain
				1 => Approximate
				_ => UncertainApproximate
			}
			if $bits % 2 == 0 {
				item = { scope, qualifier }
				$items = [item].concat($items)
				$expected = $expected.append(item)
			}
			$bits = $bits // 2
		}
		description = qualified(fractional, $items)
		if QualifiedCalendarValue.described_value(description) != fractional or QualifiedCalendarValue.qualifications(description) != $expected {
			crash "native qualification normalization changed scopes or values"
		}
		match QualifiedCalendarValue.new(fractional, [{ scope: Whole, qualifier: Uncertain }, { scope: Whole, qualifier: Approximate }]) {
			Err(DuplicateScope(Whole)) => {}
			_ => crash "duplicate native qualification accepted"
		}
		year = CalendarValue.year(calendar, 1970) ?? crash "valid year"
		match QualifiedCalendarValue.new(year, [{ scope: Day, qualifier: Uncertain }]) {
			Err(UnsuppliedComponent(Day)) => {}
			_ => crash "qualification invented unsupplied day"
		}
	}
}

# R12–R14: facts are compared with generated source fields, independently of
# diagnostic strings and native bound resolution. Rendering limits concern the
# report, never the truth of a description or the presence of an uncertainty model.
check_explanation = |value, calendar, input, h, m, s, fraction| {
	var $width = 1.U32
	var $remaining = 6.U8 - input.digits
	while $remaining > 0 {
		$width = $width * 10
		$remaining = $remaining - 1
	}
	first = match CalendarValue.fact_at(value, 0) {
		Item(fact) => SemanticFact.kind(fact)
		End => crash "Calendar explanation omitted its source"
	}
	if first != CalendarDescription({ kind: CalendarValue, calendar, fields: { year: 1970, month: 1, day: 1 }, clock: { hour: h, minute: m, second: s, microsecond: fraction * $width }, resolution: Fraction(input.digits), qualification_count: 0 }) {
		crash "Calendar facts changed generated fields or supplied fractional width"
	}
	description = qualified(value, [{ scope: Fraction, qualifier: UncertainApproximate }])
	model_fact = match QualifiedCalendarValue.fact_at(description, 2) {
		Item(fact) => SemanticFact.kind(fact)
		End => crash "Qualified description omitted its model requirement"
	}
	qualification = match QualifiedCalendarValue.fact_at(description, 3) {
		Item(fact) => SemanticFact.kind(fact)
		End => crash "Qualified description omitted supplied qualification"
	}
	if model_fact != Requirement(UncertaintyModel) or qualification != Qualification({ scope: Fraction, qualifier: UncertainApproximate }) {
		crash "Explanation lost scoped uncertainty or invented a supplied model"
	}
	source = Explanation.new(QualifiedCalendarValue(description))
	full = Explanation.plain(source, { max_facts: 16, max_utf8_bytes: 4096 })
	zero = Explanation.plain(source, { max_facts: 0, max_utf8_bytes: 4096 })
	no_text = Explanation.plain(source, { max_facts: 16, max_utf8_bytes: 0 })
	if full.status != Complete or full.visited_facts != 4 or zero.status != Limited(FactLimit) or
		!zero.text.is_empty() or zero.visited_facts != 0 or no_text.status != Limited(ByteLimit) or !no_text.text.is_empty() {
		crash "Explanation limits masqueraded as complete or consumed unbudgeted facts"
	}
	match Explanation.fact_at(source, U64.highest) {
		End => {}
		_ => crash "Out-of-range fact index must end without overflow"
	}
}
