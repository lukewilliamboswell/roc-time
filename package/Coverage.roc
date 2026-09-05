import PosixBoundary
import PosixDelta
import PosixSpan

## Canonical finite coverage on the POSIX microsecond axis.
## Members are nonempty, sorted, disjoint, and do not touch.
Coverage :: [Spans(List(PosixSpan))].{
	empty : Coverage
	empty = Spans([])

	from_spans : List(PosixSpan) -> Coverage
	from_spans = |input| {
		sorted = List.sort_with(
			input,
			|a, b| {
				match PosixBoundary.compare(PosixSpan.start(a), PosixSpan.start(b)) {
					LT => Before
					EQ => Same
					GT => After
				}
			},
		)
		var builder = { done: [], pending: None }
		for span in sorted {
			builder = push(builder, span)
		}
		Spans(finish(builder))
	}

	## Validate start ordering in O(n); merge overlap and touch.
	from_sorted_spans : List(PosixSpan) -> Try(Coverage, [UnsortedInput, ..])
	from_sorted_spans = |input| {
		var previous = None
		var builder = { done: [], pending: None }
		for span in input {
			match previous {
				None => {}
				Some(boundary) => {
					if PosixBoundary.compare(boundary, PosixSpan.start(span)) == GT {
						return Err(UnsortedInput)
					}
				}
			}
			previous = Some(PosixSpan.start(span))
			builder = push(builder, span)
		}
		Ok(Spans(finish(builder)))
	}

	## Returns the canonical spans. Roc may share their backing storage.
	to_spans : Coverage -> List(PosixSpan)
	to_spans = |Spans(items)| items

	member_count : Coverage -> U64
	member_count = |Spans(items)| List.len(items)

	## Iterate whole canonical spans, never individual microseconds.
	iter : Coverage -> Iter(PosixSpan)
	iter = |Spans(items)| List.iter(items)

	to_hash : Coverage, Hasher -> Hasher
	to_hash = |Spans(items), hasher| items.to_hash(hasher)

	to_inspect : Coverage -> Str
	to_inspect = |Spans(items)| "Coverage(${Str.inspect(items)})"

	is_eq : Coverage, Coverage -> Bool
	is_eq = |Spans(a), Spans(b)| a == b

	coordinate_width : Coverage -> Try(PosixDelta, [OutOfRange, ..])
	coordinate_width = |Spans(items)| {
		var total = 0.I64
		for span in items {
			width = PosixDelta.to_microseconds(PosixSpan.coordinate_width(span)?)
			total = match I64.plus_try(total, width) {
				Ok(value) => value
				Err(Overflow) => return Err(OutOfRange)
			}
		}
		Ok(PosixDelta.from_microseconds(total))
	}

	contains : Coverage, PosixBoundary -> Bool
	contains = |Spans(items), point| {
		index = first_end_after(items, point)
		if index == List.len(items) {
			Bool.False
		}
			else {
				PosixSpan.contains(at(items, index), point)
			}
	}

	## Fold whole overlapping members, not clipped intersections. O(log n + k).
	fold_overlaps : Coverage, PosixSpan, state, (state, PosixSpan -> state) -> state
	fold_overlaps = |Spans(items), query, initial, step| {
		var index = first_end_after(items, PosixSpan.start(query))
		var state = initial
		while index < List.len(items) {
			span = at(items, index)
			if PosixBoundary.compare(PosixSpan.start(span), PosixSpan.end(query)) != LT {
				break
			}
			state = step(state, span)
			index = index + 1
		}
		state
	}

	overlapping_spans : Coverage, PosixSpan -> List(PosixSpan)
	overlapping_spans = |coverage, query| fold_overlaps(coverage, query, [], List.append)

	union : Coverage, Coverage -> Coverage
	union = |Spans(a), Spans(b)| {
		var i = 0.U64
		var j = 0.U64
		var builder = { done: [], pending: None }
		while i < List.len(a) or j < List.len(b) {
			take_a = if i == List.len(a) {
				Bool.False
			}
				else if j == List.len(b) {
					Bool.True
				}
					else {
						PosixBoundary.compare(PosixSpan.start(at(a, i)), PosixSpan.start(at(b, j))) != GT
					}
			if take_a {
				builder = push(builder, at(a, i))
				i = i + 1
			} else {
				builder = push(builder, at(b, j))
				j = j + 1
			}
		}
		Spans(finish(builder))
	}

	intersection : Coverage, Coverage -> Coverage
	intersection = |Spans(a), Spans(b)| {
		var i = 0.U64
		var j = 0.U64
		var output = []
		while i < List.len(a) and j < List.len(b) {
			left = at(a, i)
			right = at(b, j)
			match PosixSpan.intersection(left, right) {
				Empty => {}
				Span(span) => {
					output = List.append(output, span)
				}
			}
			order = PosixBoundary.compare(PosixSpan.end(left), PosixSpan.end(right))
			if order != GT {
				i = i + 1
			}
			if order != LT {
				j = j + 1
			}
		}
		# Intersections of canonical inputs cannot touch each other.
		Spans(output)
	}

	difference : Coverage, Coverage -> Coverage
	difference = |Spans(a), Spans(b)| {
		var j = 0.U64
		var output = []
		for left in a {
			var cursor = PosixSpan.start(left)
			upper = PosixSpan.end(left)
			while j < List.len(b) and PosixBoundary.compare(cursor, upper) == LT {
				right = at(b, j)
				if PosixBoundary.compare(PosixSpan.end(right), cursor) != GT {
					j = j + 1
				} else if PosixBoundary.compare(PosixSpan.start(right), upper) != LT {
					break
				} else {
					if PosixBoundary.compare(cursor, PosixSpan.start(right)) == LT {
						output = List.append(output, fragment(cursor, PosixSpan.start(right)))
					}
					if PosixBoundary.compare(PosixSpan.end(right), upper) != LT {
						cursor = upper
						# Retain this subtrahend; it may cover the next left member.
					} else {
						cursor = PosixSpan.end(right)
						j = j + 1
					}
				}
			}
			if PosixBoundary.compare(cursor, upper) == LT {
				output = List.append(output, fragment(cursor, upper))
			}
		}
		Spans(output)
	}

	## Complement relative to one finite window; seek before emitting gaps.
	complement_within : Coverage, PosixSpan -> Coverage
	complement_within = |Spans(items), window| {
		var index = first_end_after(items, PosixSpan.start(window))
		var cursor = PosixSpan.start(window)
		upper = PosixSpan.end(window)
		var output = []
		while index < List.len(items) and PosixBoundary.compare(cursor, upper) == LT {
			span = at(items, index)
			if PosixBoundary.compare(PosixSpan.start(span), upper) != LT {
				break
			}
			if PosixBoundary.compare(cursor, PosixSpan.start(span)) == LT {
				output = List.append(output, fragment(cursor, PosixSpan.start(span)))
			}
			cursor = if PosixBoundary.compare(PosixSpan.end(span), upper) == LT {
				PosixSpan.end(span)
			} else {
				upper
			}
			index = index + 1
		}
		if PosixBoundary.compare(cursor, upper) == LT {
			output = List.append(output, fragment(cursor, upper))
		}
		Spans(output)
	}
}

# Private, invariant-backed helpers. Every index is guarded by the relevant
# list length; fragment callers establish lower < upper by endpoint comparisons.
at : List(PosixSpan), U64 -> PosixSpan
at = |items, index| {
	match List.get(items, index) {
		Ok(span) => span
		Err(OutOfBounds) => crash "coverage index invariant"
	}
}

fragment : PosixBoundary, PosixBoundary -> PosixSpan
fragment = |lower, upper| {
	match PosixSpan.new(lower, upper) {
		Ok(span) => span
		Err(_) => crash "coverage fragment invariant"
	}
}

# Output is sorted, so only the pending span can overlap the new span.
Builder : { done : List(PosixSpan), pending : [None, Some(PosixSpan)] }

push : Builder, PosixSpan -> Builder
push = |builder, span| {
	match builder.pending {
		None => { done: builder.done, pending: Some(span) }
		Some(previous) => {
			if PosixBoundary.compare(PosixSpan.start(span), PosixSpan.end(previous)) != GT {
				{ done: builder.done, pending: Some(PosixSpan.hull(previous, span)) }
			} else {
				{ done: List.append(builder.done, previous), pending: Some(span) }
			}
		}
	}
}

finish : Builder -> List(PosixSpan)
finish = |builder| {
	match builder.pending {
		None => builder.done
		Some(span) => List.append(builder.done, span)
	}
}

first_end_after : List(PosixSpan), PosixBoundary -> U64
first_end_after = |items, point| {
	var lo = 0.U64
	var hi = List.len(items)
	while lo < hi {
		mid = lo + U64.div_trunc_by(hi - lo, 2)
		if PosixBoundary.compare(PosixSpan.end(at(items, mid)), point) == GT {
			hi = mid
		} else {
			lo = mid + 1
		}
	}
	lo
}
