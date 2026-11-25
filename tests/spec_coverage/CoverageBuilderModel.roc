import fuzz.Model
import time.Coverage
import time.PosixBoundary
import time.PosixSpan

## R03/R04/R12. An ordered booking stream can keep a coverage preview, pause
## at capacity, and retry the pending span with a new capacity. The reference
## marks occupied unit cells and counts runs independently of the builder.
CoverageBuilderModel := [].{}

Bounds : { start : I64, end : I64 }

Action : [Offer({ span : Bounds, limit : U64 }), Preview]

Outcome : [Added, Full, Unsorted, Previewed]

Reference : { cells : List(Bool), previous : [None, Start(I64)] }

World : {
	builder : Coverage.SortedBuilder,
	reference : Reference,
	preview : Coverage,
	preview_cells : List(Bool),
	actual : Outcome,
	expected : Outcome,
}

positions : List(I64)
positions = [-2, -1, 0, 1, 2]

single_cells : List(Bounds)
single_cells = positions.map(|start| { start, end: start + 1 })

# Seven bounded intervals on [-2, 3) exercise overlap, touch, and three separate
# runs. The four capacities include a zero budget and one below the live count.
intervals : List(Bounds)
intervals = single_cells.concat([{ start: -2, end: 0 }, { start: 0, end: 2 }])

actions : List(Action)
actions = intervals.fold([Preview], |available, span|
	[0, 1, 2, 3].fold(available, |out, limit| out.append(Offer({ span, limit }))))

empty_cells : List(Bool)
empty_cells = [False, False, False, False, False]

machine : Model.Machine(World, Action)
machine = {
	init: {
		builder: Coverage.SortedBuilder.empty,
		reference: { cells: empty_cells, previous: None },
		preview: Coverage.empty,
		preview_cells: empty_cells,
		actual: Previewed,
		expected: Previewed,
	},
	actions: |_| actions,
	step,
	rules: [
		Model.always_step("offer reports Added, Full or UnsortedInput as specified", |{ before: _, action: _, after }|
			after.actual == after.expected),
		Model.always(
			"current and retained coverage have the expected maximal runs",
			|world| {
				expected_runs = runs(world.reference.cells)
				expected_runs == bounds(Coverage.to_spans(world.builder.to_coverage())) and
					runs(world.preview_cells) == bounds(Coverage.to_spans(world.preview)) and
						world.builder.member_count() == expected_runs.len()
			},
		),
		Model.always("start ordering uses the last admitted input, even after a pause", |world|
			single_cells.all(|span| is_unsorted(world.builder, span) == precedes_previous(world.reference, span))),
		Model.sometimes_step(
			"touching input merges at capacity while a preview is retained",
			|{ before, action, after }|
				match action {
					Offer({ span, limit }) => after.expected == Added and before.preview_cells == before.reference.cells and
						runs(before.reference.cells).len() == limit and
							runs(before.reference.cells).any(|run| run.end == span.start)
					Preview => False
				},
		),
		Model.sometimes_step(
			"decreasing input is rejected even below the previous capacity",
			|{ before, action, after }|
				match action {
					Offer({ span: _, limit }) => after.expected == Unsorted and runs(before.reference.cells).len() > limit
					Preview => False
				},
		),
		Model.sometimes_step(
			"a third disjoint run pauses while a two-run preview is retained",
			|{ before, action, after }|
				match action {
					Offer({ span: _, limit: 2 }) => after.expected == Full and before.preview_cells == before.reference.cells and
						runs(before.reference.cells).len() == 2
					_ => False
				},
		),
	],
}

step : World, Action -> World
step = |world, action| match action {
	Preview => {
		..world,
		preview: world.builder.to_coverage(),
		preview_cells: world.reference.cells,
		actual: Previewed,
		expected: Previewed,
	}
	Offer({ span, limit }) => {
		(reference, expected) = admit(world.reference, span, limit)
		match world.builder.append_bounded({ span: native_span(span), max_members: limit }) {
			Ok(Added(builder)) => { ..world, builder, reference, actual: Added, expected }
			Ok(Full(builder)) => { ..world, builder, reference, actual: Full, expected }
			Err(UnsortedInput) => { ..world, reference, actual: Unsorted, expected }
		}
	}
}

admit : Reference, Bounds, U64 -> (Reference, Outcome)
admit = |reference, span, limit| {
	if precedes_previous(reference, span) {
		return (reference, Unsorted)
	}
	cells = List.map2(reference.cells, positions, |occupied, point| occupied or (span.start <= point and point < span.end))
	if runs(cells).len() > limit {
		(reference, Full)
	} else {
		({ cells, previous: Start(span.start) }, Added)
	}
}

precedes_previous : Reference, Bounds -> Bool
precedes_previous = |reference, span| match reference.previous {
	None => False
	Start(previous) => span.start < previous
}

# Zero capacity probes the public order check without adding a member. This
# checks the otherwise hidden ordering frontier before reference keys deduplicate.
is_unsorted : Coverage.SortedBuilder, Bounds -> Bool
is_unsorted = |builder, span| match builder.append_bounded({ span: native_span(span), max_members: 0 }) {
	Err(UnsortedInput) => True
	Ok(_) => False
}

native_span : Bounds -> PosixSpan
native_span = |span|
	PosixSpan.new({
		start: PosixBoundary.from_microseconds(span.start),
		end: PosixBoundary.from_microseconds(span.end),
	}) ?? crash "coverage model interval is nonempty"

bounds : List(PosixSpan) -> List(Bounds)
bounds = |spans| spans.map(
	|span| {
		start: PosixBoundary.to_microseconds(PosixSpan.start(span)),
		end: PosixBoundary.to_microseconds(PosixSpan.end(span)),
	},
)

runs : List(Bool) -> List(Bounds)
runs = |cells| {
	var $result = []
	var $open = None
	var $point = -2.I64
	# A final empty cell flushes a run that reaches the upper edge.
	for occupied in cells.append(False) {
		match ($open, occupied) {
			(None, True) => {
				$open = Start($point)
			}
			(Start(start), False) => {
				$result = $result.append({ start, end: $point })
				$open = None
			}
			_ => {}
		}
		$point = $point + 1
	}
	$result
}

expect {
	report = Model.explore(
		machine,
		{
			depth: 12,
			key: |world| (world.reference, world.preview_cells),
			verify: EveryStep,
		},
	)
	match report.verdict {
		Holds(Exhausted) => report.unreached.is_empty()
		_ => crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
}

# Resume the actual value returned by Full. A state with the same cells and
# ordering frontier may have been reached by another path before deduplication.
expect {
	first = { start: -2.I64, end: -1.I64 }
	second = { start: 0.I64, end: 1.I64 }
	third = { start: 2.I64, end: 3.I64 }
	one = Coverage.SortedBuilder.empty.append(native_span(first))?
	two = one.append(native_span(second))?
	preview = two.to_coverage()
	match two.append_bounded({ span: native_span(third), max_members: 2 })? {
		Full(paused) => match paused.append_bounded({ span: native_span(third), max_members: 3 })? {
			Added(done) =>
				bounds(Coverage.to_spans(preview)) == [first, second] and
					bounds(Coverage.to_spans(done.to_coverage())) == [first, second, third]
			Full(_) => False
		}
		Added(_) => False
	}
}
