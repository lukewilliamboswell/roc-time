import fuzz.Fuzz
import time.Persistence
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
		var width = 1000000.I64
		var index = 0.U8
		while index < input.digits {
			width = width // 10
			index = index + 1
		}
		fraction = (I64.mod_by(number, 1000000) // width).to_u32_wrap()
		value = match CalendarValue.fractional_second(date, { hour: h, minute: m, second: s }, { value: fraction, digits: input.digits }) {
			Ok(found) => found
			Err(_) => crash "Valid decimal grid rejected"
		}
		check_calendar_persistence(input, h, m, s, fraction)
		start = (number // width) * width
		check_bounds(value, start, width)
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
		check_evidence(date, value, rules, input, start, width, after)
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
		var resumed = match first.status {
			Limited(progress) => progress.cursor
			Complete(_) => crash "Zero budget must remain incomplete"
		}
		var result = Coverage.empty
		var done = Bool.False
		var calls = 0.U64
		while calls < 4 and !done {
			batch = match ZoneRules.SelectionCursor.collect(resumed, { max_segments: 1, max_members: 2 }) {
				Ok(found) => found
				Err(_) => crash "Bounded selection failed"
			}
			match batch.status {
				Complete(coverage) => {
					result = coverage
					done = Bool.True
				}
				Limited(progress) => {
					resumed = progress.cursor
				}
			}
			calls = calls + 1
		}
		expected = if input.gap {
			Coverage.empty
		} else {
			Coverage.from_spans([span(start - 2000000, start - 2000000 + width), span(start, start + width)])
		}
		if !done or result != expected {
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
	scopes = [Whole, Year, Month, Day, Hour, Minute, Second, Fraction]
	var forward = []
	var backward = []
	var bits = number
	for scope in scopes {
		flag = match bits % 3 {
			0 => Uncertain
			1 => Approximate
			_ => UncertainApproximate
		}
		if bits % 2 == 0 {
			item = { scope, qualifier: flag }
			forward = forward.append(item)
			backward = [item].concat(backward)
		}
		bits = bits // 2
	}
	a = qualified(value, forward)
	b = qualified(value, backward)
	# Retain both input lists and a slice while canonicalization may sort them.
	sliced = [{ scope: Whole, qualifier: Uncertain }].concat(backward).drop_first(1)
	c = qualified(value, sliced)
	if a != b or a != c or QualifiedCalendarValue.qualifications(a).len() != forward.len() or QualifiedCalendarValue.described_value(a) != value {
		crash "Qualification set changed under ordering or sharing"
	}
	for item in forward {
		if !QualifiedCalendarValue.qualifications(a).contains(item) {
			crash "Qualification fact lost"
		}
	}
	if !forward.is_empty() {
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

qualified = |value, items| match QualifiedCalendarValue.new(value, items) {
	Ok(found) => found
	Err(_) => crash "Valid qualifications rejected"
}

# R13: finite-model oracle. Candidate cells are formed independently from
# decimal coordinate arithmetic. For each point, count true model rows directly
# and compare all/some/none with bounded, resumed public evidence queries.
check_evidence = |date, value, rules, input, start, width, offset| {
	description = qualified(value, [{ scope: Second, qualifier: UncertainApproximate }])
	var alternatives = []
	var starts = []
	var n = 0.I64
	minute_start = (start // 60000000) * 60000000
	original_second = (start - minute_start) // 1000000
	fraction = I64.mod_by(start, 1000000)
	while n < 4 {
		chosen_second = I64.mod_by(original_second + n, 60)
		if (input.number % 3 == 0 and n == 0) or (input.number % 3 != 0 and (input.number % 2 == 0 or n != 0)) {
			chosen = minute_start + chosen_second * 1000000 + fraction
			h = (chosen // 3600000000).to_u8_wrap()
			m = I64.mod_by(chosen // 60000000, 60).to_u8_wrap()
			candidate = match CalendarValue.fractional_second(date, { hour: h, minute: m, second: chosen_second.to_u8_wrap() }, { value: (fraction // width).to_u32_wrap(), digits: input.digits }) {
				Ok(found) => found
				Err(_) => crash "Valid evidence candidate"
			}
			alternatives = alternatives.append(candidate)
			starts = starts.append(chosen)
		}
		n = n + 1
	}
	model = match CalendarEvidence.new(description, alternatives.concat(alternatives)) {
		Ok(found) => found
		Err(_) => crash "Valid finite model rejected"
	}
	if CalendarEvidence.alternatives(model).len() != alternatives.len() {
		crash "Duplicate model rows retained"
	}
	# Both tested points occur after the synthetic transition. Exact lower and
	# upper cell endpoints exercise half-open membership without using bounds.
	for coordinate in [start, start + width] {
		local_point = coordinate + offset.to_i64() * 1000000
		var yes = 0.U64
		for lower in starts {
			if lower <= local_point and local_point < lower + width {
				yes = yes + 1
			}
		}
		expected = if yes == 0 {
			Impossible
		} else if yes == starts.len() {
			Definite
		} else {
			Possible
		}
		query = match CalendarEvidence.query(model, rules, point(coordinate)) {
			Ok(found) => found
			Err(_) => crash "Valid model point rejected"
		}
		zero = CalendarEvidence.Query.collect(query, { max_alternatives: 0 })
		var cursor = match zero.status {
			Limited(found) => found
			Complete(_) => crash "Zero work claimed complete evidence"
		}
		var finished = Bool.False
		var calls = 0.U64
		while calls < 4 and !finished {
			batch = CalendarEvidence.Query.collect(cursor, { max_alternatives: 1 })
			if batch.examined > 1 {
				crash "Evidence work budget exceeded"
			}
			match batch.status {
				Complete(truth) => {
					if truth != expected {
						crash "Finite reasoning differs from model enumeration"
					}
					finished = Bool.True
				}
				Limited(next) => {
					cursor = next
				}
			}
			calls = calls + 1
		}
		whole = CalendarEvidence.Query.collect(query, { max_alternatives: 4 })
		match whole.status {
			Complete(truth) => if !finished or truth != expected {
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
	var starts = []
	var ends = []
	var pairs = []
	var paired_spans = []
	var bits = input.number
	for coordinate in points {
		if bits % 2 == 1 {
			starts = starts.append(coordinate)
		}
		if (bits // 2) % 2 == 1 {
			ends = ends.append(coordinate)
		}
		bits = bits // 4
	}
	bits = input.number
	for start in points {
		for end in points {
			if start < end {
				if bits % 2 == 1 {
					pairs = pairs.append({ start, end })
					paired_spans = paired_spans.append(span(start, end))
				}
				bits = bits // 2
			}
		}
	}
	paired = IntervalEvidence.paired(paired_spans)
	if pairs.is_empty() {
		if paired != Err(InconsistentEvidence) {
			crash "Empty paired evidence succeeded"
		}
	} else {
		evidence = match paired {
			Ok(found) => found
			Err(_) => crash "Valid paired evidence rejected"
		}
		sliced = [span(center - 1, center)].concat(paired_spans.concat(paired_spans)).drop_first(1)
		if IntervalEvidence.paired(sliced) != Ok(evidence) {
			crash "Shared paired normalization changed declaration"
		}
		check_interval_truth(evidence, pairs, points)
	}
	var admissible = []
	for start in starts {
		for end in ends {
			if start < end {
				admissible = admissible.append({ start, end })
			}
		}
	}
	start_points = starts.map(point)
	end_points = ends.map(point)
	independent = IntervalEvidence.independent({ starts: start_points, ends: end_points })
	if admissible.is_empty() {
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
		check_interval_truth(evidence, admissible, points)
	}
}

check_interval_truth = |evidence, intervals, points| {
	for coordinate in points {
		var yes = 0.U64
		for interval in intervals {
			if interval.start <= coordinate and coordinate < interval.end {
				yes = yes + 1
			}
		}
		expected = if yes == 0 {
			Impossible
		} else if yes == intervals.len() {
			Definite
		} else {
			Possible
		}
		if IntervalEvidence.contains(evidence, point(coordinate)) != expected {
			crash "Interval truth differs from exhaustive admissible model"
		}
		if Coverage.contains(IntervalEvidence.possible_coverage(evidence), point(coordinate)) != (yes > 0) or
			Coverage.contains(IntervalEvidence.definite_coverage(evidence), point(coordinate)) != (yes == intervals.len()) {
			crash "Interval coverage projections differ from quantified membership"
		}
	}
}

# R02/R14: native persistence retains calendar identity and every supplied
# resolution. Expected payloads come from generated fields, not native bounds
# or the serializer. Provider limits persist without any POSIX materialization.
check_calendar_persistence = |input, h, m, s, fraction| {
	for calendar in [Gregorian, Julian] {
		name = match calendar {
			Gregorian => "gregorian"
			Julian => "julian"
		}
		date = match CalendarDate.from_fields(calendar, { year: 1970, month: 1, day: 1 }) {
			Ok(found) => found
			Err(_) => crash "Valid native persistence date"
		}
		year = match CalendarValue.year(calendar, 1970) {
			Ok(found) => found
			Err(_) => crash "Valid native year"
		}
		month = match CalendarValue.month(calendar, 1970, 1) {
			Ok(found) => found
			Err(_) => crash "Valid native month"
		}
		hour = match CalendarValue.hour(date, h) {
			Ok(found) => found
			Err(_) => crash "Valid native hour"
		}
		minute = match CalendarValue.minute(date, h, m) {
			Ok(found) => found
			Err(_) => crash "Valid native minute"
		}
		second = match CalendarValue.second(date, h, m, s) {
			Ok(found) => found
			Err(_) => crash "Valid native second"
		}
		fractional = match CalendarValue.fractional_second(date, { hour: h, minute: m, second: s }, { digits: input.digits, value: fraction }) {
			Ok(found) => found
			Err(_) => crash "Valid native fractional cell"
		}
		fraction_payload = "${name};fraction;1970;1;1;${h.to_str()};${m.to_str()};${s.to_str()};${input.digits.to_str()};${fraction.to_str()}"
		for item in [
			{ value: year, payload: "${name};year;1970" },
			{ value: month, payload: "${name};month;1970;1" },
			{ value: CalendarValue.day(date), payload: "${name};day;1970;1;1" },
			{ value: hour, payload: "${name};hour;1970;1;1;${h.to_str()}" },
			{ value: minute, payload: "${name};minute;1970;1;1;${h.to_str()};${m.to_str()}" },
			{ value: second, payload: "${name};second;1970;1;1;${h.to_str()};${m.to_str()};${s.to_str()}" },
			{ value: fractional, payload: fraction_payload },
		] {
			check_calendar_envelope(CalendarValue(item.value), "calendar-value", "native-calendar-value-v1", item.payload)
		}
		for limit in [-2147483648.I64, 2147483647] {
			value = match CalendarValue.year(calendar, limit) {
				Ok(found) => found
				Err(_) => crash "Supported provider year limit rejected"
			}
			check_calendar_envelope(CalendarValue(value), "calendar-value", "native-calendar-value-v1", "${name};year;${limit.to_str()}")
		}
		# Qualifier scope and flags are independent. Generate an ordered oracle
		# list, supply it reversed, and require canonical scope order on restore.
		scopes : List({ scope : QualifiedCalendarValue.Scope, name : Str })
		scopes = [{ scope: Whole, name: "whole" }, { scope: Year, name: "year" }, { scope: Month, name: "month" }, { scope: Day, name: "day" }, { scope: Hour, name: "hour" }, { scope: Minute, name: "minute" }, { scope: Second, name: "second" }, { scope: Fraction, name: "fraction" }]
		var items = []
		var expected = []
		var reversed = []
		var bits = input.number
		for choice in scopes {
			flag = match bits % 3 {
				0 => { value: Uncertain, name: "uncertain" }
				1 => { value: Approximate, name: "approximate" }
				_ => { value: UncertainApproximate, name: "uncertain-approximate" }
			}
			if bits % 2 == 0 {
				items = [{ scope: choice.scope, qualifier: flag.value }].concat(items)
				token = "${choice.name}=${flag.name}"
				expected = expected.append(token)
				reversed = [token].concat(reversed)
			}
			bits = bits // 2
		}
		description = qualified(fractional, items)
		payload = "${fraction_payload}|${Str.join_with(expected, ";")}"
		check_calendar_envelope(QualifiedCalendarValue(description), "qualified-calendar-value", "native-qualified-calendar-value-v1", payload)
		noncanonical = calendar_envelope("qualified-calendar-value", "native-qualified-calendar-value-v1", "${fraction_payload}|${Str.join_with(reversed, ";")}")
		match Persistence.parse(noncanonical) {
			Ok(found) => if Persistence.value(found) != QualifiedCalendarValue(description) {
				crash "Qualifier order changed persisted meaning"
			}
			Err(_) => crash "Valid reordered persisted qualifiers rejected"
		}
		duplicate = calendar_envelope("qualified-calendar-value", "native-qualified-calendar-value-v1", "${fraction_payload}|whole=uncertain;whole=approximate")
		match Persistence.parse(duplicate) {
			Err(InvalidQualifiedCalendarValue(DuplicateScope(Whole))) => {}
			_ => crash "Persisted duplicate qualifier scope accepted"
		}
		unsupplied = calendar_envelope("qualified-calendar-value", "native-qualified-calendar-value-v1", "${name};year;1970|day=uncertain")
		match Persistence.parse(unsupplied) {
			Err(InvalidQualifiedCalendarValue(UnsuppliedComponent(Day))) => {}
			_ => crash "Persistence invented unsupplied qualified component"
		}
	}
}

calendar_envelope : Str, Str, Str -> Str
calendar_envelope = |kind, profile, payload| Json.to_str({ format: "roc-time", version: "1", kind, profile, axis: "none", unit: "none", payload })

check_calendar_envelope = |value, kind, profile, payload| {
	native = match Persistence.new(value) {
		Ok(found) => found
		Err(_) => crash "Bounded native calendar persistence failed"
	}
	expected = calendar_envelope(kind, profile, payload)
	if Persistence.to_text(native) != expected {
		crash "Native calendar persistence differs from generated field oracle"
	}
	match Persistence.parse(expected) {
		Ok(found) => if Persistence.value(found) != value or Persistence.to_text(found) != expected {
			crash "Calendar persistence lost native identity or canonical text"
		}
		Err(_) => crash "Valid native calendar persistence rejected"
	}
}
