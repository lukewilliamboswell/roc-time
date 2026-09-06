import PosixBoundary
import PosixDelta
import PosixSpan

## Canonical finite coverage on the POSIX microsecond axis.
## Members are nonempty, sorted, disjoint, and do not touch.
##
## Example
##
## Combine occupied spans, then subtract them from a finite availability window.
## Overlapping or touching spans coalesce. Keep bookings in `EventCollection`
## when their individual identities matter; coverage deliberately forgets them.
##
## ```roc
## import time.Coverage
## import time.PosixSpan
## import time.PosixDelta
##
## expect {
##     window = PosixSpan.from_seconds(0, 10, RejectSubmicrosecond)?
##     busy = Coverage.from_spans([
##         PosixSpan.from_seconds(2, 4, RejectSubmicrosecond)?,
##         PosixSpan.from_seconds(4, 6, RejectSubmicrosecond)?,
##     ])
##     free = Coverage.difference(Coverage.from_spans([window]), busy)
##     expected_width = PosixDelta.from_microseconds(6000000)
##     Coverage.member_count(busy) == 1 and
##         Coverage.member_count(free) == 2 and
##         Coverage.coordinate_width(free) == Ok(expected_width)
## }
## ```
##
## Examples assume a package dependency named `time`.
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
		var builder = SortedBuilder.empty
		for span in input {
			builder = SortedBuilder.append(builder, span)?
		}
		Ok(SortedBuilder.to_coverage(builder))
	}

	## Incremental construction from start-ordered spans, including across input
	## chunks. Retains canonical output plus one pending span, not all raw input.
	## This materializes coverage; it is not a lazy output iterator. Retaining a
	## builder/snapshot can cause subsequent List appends to copy shared storage.
	SortedBuilder :: { state : Builder, previous : [None, Some(PosixBoundary)] }.{
		empty : SortedBuilder
		empty = { state: { done: [], pending: None }, previous: None }
		member_count : SortedBuilder -> U64
		member_count = |builder| builder.state.done.len() + match builder.state.pending {
			None => 0
			Some(_) => 1
		}

		## Constant comparison work; owned append is amortized, shared append may
		## copy retained output. Equal starts are valid; decreasing starts fail.
		append : SortedBuilder, PosixSpan -> Try(SortedBuilder, [UnsortedInput, ..])
		append = |builder, span| match append_bounded(builder, span, U64.highest)? {
			Added(updated) => Ok(updated)
			Full => crash "Allocated span list cannot exhaust U64 member count"
		}

		## Full leaves the input builder unchanged and performs no output append.
		## The limit counts canonical members, so touching/overlapping input can
		## still merge at capacity. An already larger builder also returns Full.
		append_bounded : SortedBuilder, PosixSpan, U64 -> Try([Added(SortedBuilder), Full], [UnsortedInput, ..])
		append_bounded = |builder, span, limit| match append_retaining(builder, span, limit)? {
			Added(updated) => Ok(Added(updated))
			Full(_) => Ok(Full)
		}

		## Internal cursor integration: return ownership of an unchanged full
		## builder so callers need not retain an alias across a successful append.
		## The public append_bounded adapter uses this same validation and merge.
		append_retaining : SortedBuilder, PosixSpan, U64 -> Try([Added(SortedBuilder), Full(SortedBuilder)], [UnsortedInput, ..])
		append_retaining = |builder, span, limit| {
			match builder.previous {
				Some(previous) => if previous > PosixSpan.start(span) {
					return Err(UnsortedInput)
				}
				None => {}
			}
			adds_member = match builder.state.pending {
				None => Bool.True
				Some(previous) => PosixSpan.start(span) > PosixSpan.end(previous)
			}
			count = member_count(builder)
			if count > limit or (adds_member and count == limit) {
				return Ok(Full(builder))
			}
			Ok(Added({ state: push(builder.state, span), previous: Some(PosixSpan.start(span)) }))
		}

		## No revalidation or sorting. Appending the pending member can copy a
		## shared list; this does not detach earlier snapshots' backing storage.
		to_coverage : SortedBuilder -> Coverage
		to_coverage = |builder| Spans(finish(builder.state))
		to_inspect : SortedBuilder -> Str
		to_inspect = |builder| "Coverage.SortedBuilder(members=${member_count(builder).to_str()})"
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
	to_inspect = |Spans(items)| {
		count = List.len(items)
		var index = 0.U64
		var preview = ""
		# A fixed four-member budget; no full-list traversal or width calculation.
		while index < count and index < 4 {
			separator = if index == 0 {
				""
			} else {
				", "
			}
			preview = "${preview}${separator}${Str.inspect(at(items, index))}"
			index = index + 1
		}
		omitted = if count > index {
			", omitted=${(count - index).to_str()}"
		} else {
			""
		}
		"Coverage(members=${count.to_str()}, preview=[${preview}]${omitted})"
	}

	expect Str.inspect(empty) == "Coverage(members=0, preview=[])"

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

# Capacity counts canonical members, so touching chunks can merge at capacity.
expect {
	a = PosixSpan.new(PosixBoundary.from_microseconds(0), PosixBoundary.from_microseconds(10))?
	b = PosixSpan.new(PosixBoundary.from_microseconds(10), PosixBoundary.from_microseconds(12))?
	c = PosixSpan.new(PosixBoundary.from_microseconds(14), PosixBoundary.from_microseconds(15))?
	first = Coverage.SortedBuilder.append(Coverage.SortedBuilder.empty, a)?
	snapshot = Coverage.SortedBuilder.to_coverage(first)
	match Coverage.SortedBuilder.append_bounded(first, b, 1)? {
		Full => False
		Added(second) => {
			blocked = match Coverage.SortedBuilder.append_bounded(second, c, 1)? {
				Full => True
				_ => False
			}
			# A merged hull must not hide decreasing original input starts.
			unsorted = match Coverage.SortedBuilder.append(second, a) {
				Err(UnsortedInput) => True
				_ => False
			}
			third = Coverage.SortedBuilder.append(second, c)?
			blocked and unsorted and snapshot == Coverage.from_spans([a]) and
				Coverage.SortedBuilder.to_coverage(third) == Coverage.from_spans([a, b, c])
		}
	}
}

# All 16 subsets of [-2, 2), independently represented by four integer bits.
test_coverage_from_mask = |mask| {
	var spans = []
	for (point, bit) in [(-2.I64, 1.U64), (-1, 2), (0, 4), (1, 8)] {
		if U64.rem_by(U64.div_trunc_by(mask, bit), 2) == 1 {
			spans = List.append(spans, PosixSpan.microsecond_at(PosixBoundary.from_microseconds(point))?)
		}
	}
	Ok(Coverage.from_spans(spans))
}

expect {
	window = PosixSpan.new(PosixBoundary.from_microseconds(-2), PosixBoundary.from_microseconds(2))?
	universe = Coverage.from_spans([window])
	var valid = Bool.True
	var x = 0.U64
	while x < 16 {
		a = test_coverage_from_mask(x)?
		valid = valid and Coverage.from_spans(Coverage.to_spans(a)) == a
		valid = valid and Coverage.union(a, a) == a and Coverage.intersection(a, a) == a
		complement = Coverage.complement_within(a, window)
		valid = valid and Coverage.union(a, complement) == universe
		valid = valid and Coverage.intersection(a, complement) == Coverage.empty
		var expected_width = 0.I64
		var expected_members = 0.U64
		var previous = Bool.False
		for bit in [1.U64, 2, 4, 8] {
			occupied = U64.rem_by(U64.div_trunc_by(x, bit), 2) == 1
			if occupied {
				expected_width = expected_width + 1
			}
			if occupied and !previous {
				expected_members = expected_members + 1
			}
			previous = occupied
		}
		valid = valid and Coverage.coordinate_width(a) == Ok(PosixDelta.from_microseconds(expected_width))
		valid = valid and Coverage.member_count(a) == expected_members
		var y = 0.U64
		while y < 16 {
			b = test_coverage_from_mask(y)?
			union = Coverage.union(a, b)
			intersection = Coverage.intersection(a, b)
			difference = Coverage.difference(a, b)
			valid = valid and union == Coverage.union(b, a)
			valid = valid and intersection == Coverage.intersection(b, a)
			valid = valid and Coverage.intersection(difference, b) == Coverage.empty
			valid = valid and Coverage.union(difference, intersection) == a
			for (point, bit) in [(-2.I64, 1.U64), (-1, 2), (0, 4), (1, 8)] {
				in_a = U64.rem_by(U64.div_trunc_by(x, bit), 2) == 1
				in_b = U64.rem_by(U64.div_trunc_by(y, bit), 2) == 1
				boundary = PosixBoundary.from_microseconds(point)
				valid = valid and Coverage.contains(a, boundary) == in_a
				valid = valid and Coverage.contains(union, boundary) == (in_a or in_b)
				valid = valid and Coverage.contains(intersection, boundary) == (in_a and in_b)
				valid = valid and Coverage.contains(difference, boundary) == (in_a and !in_b)
				valid = valid and Coverage.contains(complement, boundary) == !in_a
			}
			for outside in [-3.I64, 2] {
				point = PosixBoundary.from_microseconds(outside)
				valid = valid and !Coverage.contains(union, point)
				valid = valid and !Coverage.contains(difference, point)
				valid = valid and !Coverage.contains(complement, point)
			}
			y = y + 1
		}
		x = x + 1
	}
	valid
}

# Arbitrarily overlapping inputs, duplicate spans, reverse order, and queries
# clipping each possible endpoint. Compare directly to integer membership.
expect {
	var valid = Bool.True
	for a in [-2.I64, -1, 0, 1] {
		for b in [-1.I64, 0, 1, 2] {
			for c in [-2.I64, -1, 0, 1] {
				for d in [-1.I64, 0, 1, 2] {
					if a < b and c < d {
						left = PosixSpan.new(PosixBoundary.from_microseconds(a), PosixBoundary.from_microseconds(b))?
						right = PosixSpan.new(PosixBoundary.from_microseconds(c), PosixBoundary.from_microseconds(d))?
						coverage = Coverage.from_spans([left, right, left])
						valid = valid and coverage == Coverage.from_spans([right, left])
						clipped = Coverage.intersection(coverage, Coverage.from_spans([left]))
						complement = Coverage.complement_within(Coverage.from_spans([right]), left)
						valid = valid and Coverage.union(complement, Coverage.intersection(Coverage.from_spans([right]), Coverage.from_spans([left]))) == Coverage.from_spans([left])
						matches = Coverage.overlapping_spans(coverage, left)
						count = Coverage.fold_overlaps(coverage, left, 0.U64, |n, _| n + 1)
						valid = valid and count == List.len(matches)
						# Linear query oracle includes only whole overlapping members.
						var expected_matches = []
						for member in Coverage.to_spans(coverage) {
							if PosixSpan.overlaps(member, left) {
								expected_matches = List.append(expected_matches, member)
							}
						}
						valid = valid and matches == expected_matches
						for p in [-3.I64, -2, -1, 0, 1, 2, 3] {
							point = PosixBoundary.from_microseconds(p)
							occupied = (a <= p and p < b) or (c <= p and p < d)
							valid = valid and Coverage.contains(coverage, point) == occupied
							valid = valid and Coverage.contains(clipped, point) == (a <= p and p < b)
							valid = valid and Coverage.contains(complement, point) == (a <= p and p < b and !(c <= p and p < d))
						}
					}
				}
			}
		}
	}
	valid
}

expect {
	early = PosixSpan.new(PosixBoundary.from_microseconds(-2), PosixBoundary.from_microseconds(0))?
	late = PosixSpan.new(PosixBoundary.from_microseconds(0), PosixBoundary.from_microseconds(2))?
	Coverage.from_sorted_spans([early, late]) == Ok(Coverage.from_spans([late, early])) and
		Coverage.from_sorted_spans([late, early]) == Err(UnsortedInput)
}

expect {
	wide = PosixSpan.new(PosixBoundary.from_microseconds(-9223372036854775808), PosixBoundary.from_microseconds(-1))?
	unit = PosixSpan.microsecond_at(PosixBoundary.from_microseconds(0))?
	Coverage.coordinate_width(Coverage.from_spans([wide, unit])) == Err(OutOfRange)
}

expect {
	unit = PosixSpan.microsecond_at(PosixBoundary.from_microseconds(9223372036854775806))?
	coverage = Coverage.from_spans([unit])
	Coverage.contains(coverage, PosixSpan.start(unit)) and !Coverage.contains(coverage, PosixSpan.end(unit)) and
		Coverage.complement_within(coverage, unit) == Coverage.empty
}
