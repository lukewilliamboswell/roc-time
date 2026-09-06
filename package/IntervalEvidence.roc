import PosixBoundary
import PosixSpan
import Coverage

## Finite evidence for one unknown nonempty POSIX interval, profile
## finite-posix-interval-alternatives-v1. Endpoints use signed I64 microseconds.
## Paired choices preserve correlation. Independent choices admit every start/end
## combination with start < end; invalid combinations are not interpretations.
## Empty admissible evidence errors. Unknown/unbounded and civil descriptions
## require separate explicit interpretation; no zone or tolerance is inferred.
##
## Construction accepts at most 4096 spans or 4096 endpoints on each side,
## normalizes inputs in O(n log n) and retains O(n) input/summary storage.
## Independent construction never materializes the Cartesian product. Point
## queries cost O(log n) for paired choices and O(1) for independent choices.
IntervalEvidence :: { declaration : Declaration, possible : Coverage, definite : Coverage }.{
	Declaration : [Paired(List(PosixSpan)), Independent({ starts : List(PosixBoundary), ends : List(PosixBoundary) })]
	Truth : [Definite, Possible, Impossible]
	profile : Str
	profile = "finite-posix-interval-alternatives-v1"
	paired : List(PosixSpan) -> Try(IntervalEvidence, [InconsistentEvidence, TooManyAlternatives, ..])
	paired = |choices| {
		if choices.is_empty() {
			return Err(InconsistentEvidence)
		}
		if choices.len() > 4096 {
			return Err(TooManyAlternatives)
		}
		sorted = choices.sort_with(
			|a, b| {
				comparison = PosixBoundary.compare(PosixSpan.start(a), PosixSpan.start(b))
				final = if comparison == EQ {
					PosixBoundary.compare(PosixSpan.end(a), PosixSpan.end(b))
				} else {
					comparison
				}
				ordering(final)
			},
		)
		var canonical = []
		for span in sorted {
			if canonical.last() != Ok(span) {
				canonical = canonical.append(span)
			}
		}
		first = at(canonical, 0)
		var latest_start = PosixSpan.start(first)
		var earliest_end = PosixSpan.end(first)
		for span in canonical {
			if PosixSpan.start(span) > latest_start {
				latest_start = PosixSpan.start(span)
			}
			if PosixSpan.end(span) < earliest_end {
				earliest_end = PosixSpan.end(span)
			}
		}
		Ok({ declaration: Paired(canonical), possible: Coverage.from_spans(canonical), definite: between(latest_start, earliest_end) })
	}
	independent : { starts : List(PosixBoundary), ends : List(PosixBoundary) } -> Try(IntervalEvidence, [InconsistentEvidence, TooManyAlternatives, ..])
	independent = |choices| {
		if choices.starts.is_empty() or choices.ends.is_empty() {
			return Err(InconsistentEvidence)
		}
		if choices.starts.len() > 4096 or choices.ends.len() > 4096 {
			return Err(TooManyAlternatives)
		}
		starts = normalize(choices.starts)
		ends = normalize(choices.ends)
		first_start = at(starts, 0)
		last_end = at(ends, ends.len() - 1)
		if first_start >= last_end {
			return Err(InconsistentEvidence)
		}
		# (first_start,last_end) is itself admissible and contains every other
		# valid combination, so existential membership is this one whole span.
		# Universal membership uses only endpoints participating in valid pairs.
		# A start is viable iff start < last_end; an end iff end > first_start.
		var latest_start = first_start
		for start in starts {
			if start < last_end {
				latest_start = start
			}
		}
		var earliest_end = last_end
		for end in ends {
			if end > first_start {
				earliest_end = end
				break
			}
		}
		Ok({ declaration: Independent({ starts, ends }), possible: between(first_start, last_end), definite: between(latest_start, earliest_end) })
	}

	## Definite means every admissible interval contains the point; Possible
	## means some but not all; Impossible means none. Queries do not allocate
	## or enumerate pairs and can include either I64 boundary without overflow.
	contains : IntervalEvidence, PosixBoundary -> Truth
	contains = |evidence, point| if Coverage.contains(evidence.definite, point) {
		Definite
	} else if Coverage.contains(evidence.possible, point) {
		Possible
	} else {
		Impossible
	}

	## Existential union and universal intersection, respectively. These are
	## explicit projections of evidence, not the unknown actual interval.
	possible_coverage : IntervalEvidence -> Coverage
	possible_coverage = |evidence| evidence.possible
	definite_coverage : IntervalEvidence -> Coverage
	definite_coverage = |evidence| evidence.definite
	declaration : IntervalEvidence -> Declaration
	declaration = |evidence| evidence.declaration

	## Declaration equality preserves paired versus independent intent and all
	## normalized supplied choices, including nonparticipating endpoint values.
	## This does not claim equivalence for all interval-reasoning propositions.
	is_eq : IntervalEvidence, IntervalEvidence -> Bool
	is_eq = |a, b| a.declaration == b.declaration
	to_hash : IntervalEvidence, Hasher -> Hasher
	to_hash = |evidence, hasher| match evidence.declaration {
		Paired(choices) => {
			var state = (0.U8).to_hash(hasher)
			for span in choices {
				state = span.to_hash(state)
			}
			choices.len().to_hash(state)
		}
		Independent(choices) => {
			var state = (1.U8).to_hash(hasher)
			for point in choices.starts {
				state = point.to_hash(state)
			}
			state = choices.starts.len().to_hash(state)
			for point in choices.ends {
				state = point.to_hash(state)
			}
			choices.ends.len().to_hash(state)
		}
	}
	to_inspect : IntervalEvidence -> Str
	to_inspect = |evidence| match evidence.declaration {
		Paired(choices) => "IntervalEvidence(Paired, alternatives=${choices.len().to_str()})"
		Independent(choices) => "IntervalEvidence(Independent, starts=${choices.starts.len().to_str()}, ends=${choices.ends.len().to_str()})"
	}
}

ordering = |value| match value {
	LT => Before
	EQ => Same
	GT => After
}

normalize = |points| {
	sorted = points.sort_with(|a, b| ordering(PosixBoundary.compare(a, b)))
	var canonical = []
	for point in sorted {
		if canonical.last() != Ok(point) {
			canonical = canonical.append(point)
		}
	}
	canonical
}

at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(_) => crash "Nonempty normalized interval evidence invariant"
}

between = |start, end| if start < end {
	span = match PosixSpan.new(start, end) {
		Ok(value) => value
		Err(_) => crash "Ordered evidence summary bounds"
	}
	Coverage.from_spans([span])
} else {
	Coverage.empty
}

expect {
	paired = IntervalEvidence.paired([test_span(0, 1)?, test_span(2, 3)?])?
	independent = IntervalEvidence.independent({ starts: [point(0), point(2)], ends: [point(1), point(3)] })?
	IntervalEvidence.contains(paired, point(1)) == Impossible and IntervalEvidence.contains(independent, point(1)) == Possible
}
expect {
	# Only (0,1) is valid. Neither invalid (2,1) nor (0,-1) is a counterexample
	# to universal membership. This breaks an unfiltered-extrema implementation.
	evidence = IntervalEvidence.independent({ starts: [point(2), point(0)], ends: [point(-1), point(1)] })?
	IntervalEvidence.contains(evidence, point(0)) == Definite and IntervalEvidence.contains(evidence, point(1)) == Impossible
}
expect {
	IntervalEvidence.paired([]) == Err(InconsistentEvidence) and
		IntervalEvidence.independent({ starts: [point(0)], ends: [] }) == Err(InconsistentEvidence) and
			IntervalEvidence.independent({ starts: [point(2)], ends: [point(1), point(2)] }) == Err(InconsistentEvidence) and
				IntervalEvidence.independent({ starts: List.repeat(point(0), 4097), ends: [point(1)] }) == Err(TooManyAlternatives)
}
expect {
	value = IntervalEvidence.independent({ starts: [point(I64.lowest), point(I64.highest)], ends: [point(I64.lowest), point(I64.highest)] })?
	IntervalEvidence.contains(value, point(I64.lowest)) == Definite and
		IntervalEvidence.contains(value, point(I64.highest)) == Impossible and
			IntervalEvidence.contains(value, point(0)) == Definite
}
point = PosixBoundary.from_microseconds

test_span = |start, end| PosixSpan.new(point(start), point(end))

expect {
	# Identical pointwise projections do not erase the declared interpretations.
	a = IntervalEvidence.paired([test_span(0, 2)?, test_span(1, 3)?])?
	b = IntervalEvidence.paired([test_span(0, 2)?, test_span(1, 3)?, test_span(0, 3)?])?
	a != b and IntervalEvidence.possible_coverage(a) == IntervalEvidence.possible_coverage(b) and
		IntervalEvidence.definite_coverage(a) == IntervalEvidence.definite_coverage(b)
}
