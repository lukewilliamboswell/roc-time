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
