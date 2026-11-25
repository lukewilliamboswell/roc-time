import time.Coverage
import time.PosixBoundary
import time.PosixSpan

## R03/R04. Availability can span the entire signed coordinate domain even
## when its width cannot be represented as an I64 displacement.
WideCoverage := [].{}

Bounds : { start : I64, end : I64 }

edges : List(I64)
edges = [I64.lowest, I64.lowest + 1, 0, I64.highest - 1, I64.highest]

# Four elementary cells replace enumeration of the individual microseconds.
# Every tested input/window changes membership only at one of these edges.
cells : List(Bounds)
cells = List.map2(edges, edges.drop_first(1), |start, end| { start, end })

native : Bounds -> PosixSpan
native = |{ start, end }|
	PosixSpan.new({ start: PosixBoundary.from_microseconds(start), end: PosixBoundary.from_microseconds(end) }) ?? crash "nonempty fixture span"

bounds : PosixSpan -> Bounds
bounds = |span| {
	start: PosixBoundary.to_microseconds(PosixSpan.start(span)),
	end: PosixBoundary.to_microseconds(PosixSpan.end(span)),
}

# Rebuild each maximal run from consecutive true cells, with its upper
# endpoint provided by the first false cell or the final domain edge.
runs : List(Bool) -> List(Bounds)
runs = |occupancy| {
	var $start = None
	var $out = []
	for (edge, occupied) in List.map2(edges, occupancy.append(False), |edge, occupied| (edge, occupied)) {
		match ($start, occupied) {
			(None, True) => {
				$start = Some(edge)
			}
			(Some(start), False) => {
				$out = $out.append({ start, end: edge })
				$start = None
			}
			_ => {}
		}
	}
	$out
}

Profile : { occupied : List(Bool), coverage : Coverage }

profiles : List(Profile)
profiles = {
	var $mask = 0.U64
	var $out = []
	while $mask < 16 {
		mask = $mask
		occupied = [1.U64, 2, 4, 8].map(|bit| U64.rem_by(U64.div_trunc_by(mask, bit), 2) == 1)
		input = List.map2(cells, occupied, |cell, take| (cell, take)).keep_if(|(_, take)| take).map(|(cell, _)| native(cell))
		$out = $out.append({ occupied, coverage: Coverage.from_spans(input) })
		$mask = $mask + 1
	}
	$out
}

expect {
	var $valid = Bool.True
	for a in profiles {
		original = runs(a.occupied)
		for b in profiles {
			merged = runs(List.map2(a.occupied, b.occupied, |aa, bb| aa or bb))
			common = runs(List.map2(a.occupied, b.occupied, |aa, bb| aa and bb))
			remaining = runs(List.map2(a.occupied, b.occupied, |aa, bb| aa and !bb))
			$valid = $valid and Coverage.to_spans(Coverage.union(a.coverage, b.coverage)).map(bounds) == merged and
				Coverage.to_spans(Coverage.intersection(a.coverage, b.coverage)).map(bounds) == common and
					Coverage.to_spans(Coverage.difference({ base: a.coverage, subtract: b.coverage })).map(bounds) == remaining
		}
		for start in edges {
			for end in edges.keep_if(|edge| start < edge) {
				window = native({ start, end })
				free = runs(List.map2(cells, a.occupied, |cell, taken| start <= cell.start and cell.end <= end and !taken))
				whole = original.keep_if(|run| start < run.end and run.start < end)
				if Coverage.to_spans(Coverage.complement_within(a.coverage, window)).map(bounds) != free or
					Coverage.overlapping_spans(a.coverage, window).map(bounds) != whole {
					crash "Wide query ${Str.inspect({ start, end })} differs for occupied runs ${Str.inspect(original)}"
				}
			}
		}
		for (cell, occupied) in List.map2(cells, a.occupied, |cell, occupied| (cell, occupied)) {
			$valid = $valid and Coverage.contains(a.coverage, PosixBoundary.from_microseconds(cell.start)) == occupied
		}
		$valid = $valid and !Coverage.contains(a.coverage, PosixBoundary.from_microseconds(I64.highest)) and
			Coverage.to_spans(a.coverage).map(bounds) == original
	}
	$valid
}
