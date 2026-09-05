import Coverage
import LocalDateTime
import ZoneRules

## Complete local-selection coverage retaining its exact interpretation inputs.
ResolvedSelection :: {
	start : LocalDateTime,
	end : LocalDateTime,
	rules : ZoneRules,
	coverage : Coverage,
}.{
	resolve : ZoneRules, LocalDateTime, LocalDateTime -> Try(ResolvedSelection, [EmptySelection, ReversedSelection, OutsideValidity, OutOfRange, ..])
	resolve = |rules, start, end| {
		coverage = ZoneRules.select(rules, start, end)?
		Ok({ start, end, rules, coverage })
	}

	Batch : {
		segments : U64,
		buffered : U64,
		status : [Complete(ResolvedSelection), Limited({ cursor : ZoneRules.SelectionCursor, reason : [WorkLimit, BufferLimit] })],
	}

	## Continue a validated zone-selection cursor under explicit work/storage
	## limits. Only complete interpretation becomes a snapshot. The cursor
	## retains the exact rules and civil inputs across all resumptions.
	collect : ZoneRules.SelectionCursor, ZoneRules.SelectionLimits -> Try(Batch, [OutOfRange, ..])
	collect = |cursor, limits| {
		batch = ZoneRules.SelectionCursor.collect(cursor, limits)?
		status = match batch.status {
			Limited(progress) => Limited(progress)
			Complete(coverage) => {
				context = ZoneRules.SelectionCursor.context(cursor)
				Complete({ start: context.start, end: context.end, rules: context.rules, coverage })
			}
		}
		Ok({ segments: batch.segments, buffered: batch.buffered, status })
	}

	coverage : ResolvedSelection -> Coverage
	coverage = |snapshot| snapshot.coverage
	start : ResolvedSelection -> LocalDateTime
	start = |snapshot| snapshot.start
	end : ResolvedSelection -> LocalDateTime
	end = |snapshot| snapshot.end
	rules : ResolvedSelection -> ZoneRules
	rules = |snapshot| snapshot.rules

	reresolve : ResolvedSelection, ZoneRules -> Try(ResolvedSelection, [EmptySelection, ReversedSelection, OutsideValidity, OutOfRange, ..])
	reresolve = |snapshot, new_rules| resolve(new_rules, snapshot.start, snapshot.end)

	same_extent : ResolvedSelection, ResolvedSelection -> Bool
	same_extent = |a, b| a.coverage == b.coverage

	to_inspect : ResolvedSelection -> Str
	to_inspect = |snapshot| "ResolvedSelection(${Str.inspect(snapshot.coverage)}, start=${Str.inspect(snapshot.start)}, end=${Str.inspect(snapshot.end)})"
}
