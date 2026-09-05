import FixedOffset
import LocalDateTime
import PosixBoundary
import ZoneRules

## A resolved occurrence with the exact immutable inputs that produced it.
ResolvedBoundary :: {
	source : LocalDateTime,
	policy : ZoneRules.OccurrencePolicy,
	rules : ZoneRules,
	boundary : PosixBoundary,
	offset : FixedOffset,
}.{
	resolve : ZoneRules, LocalDateTime, ZoneRules.OccurrencePolicy -> Try(ResolvedBoundary, [Gap, Ambiguous, OffsetConflict, OutsideValidity, OutOfRange, ..])
	resolve = |rules, source, policy| {
		boundary = ZoneRules.resolve_occurrence(rules, source, policy)?
		offset = ZoneRules.offset_at(rules, boundary)?
		Ok({ source, policy, rules, boundary, offset })
	}

	boundary : ResolvedBoundary -> PosixBoundary
	boundary = |snapshot| snapshot.boundary
	source : ResolvedBoundary -> LocalDateTime
	source = |snapshot| snapshot.source
	policy : ResolvedBoundary -> ZoneRules.OccurrencePolicy
	policy = |snapshot| snapshot.policy
	rules : ResolvedBoundary -> ZoneRules
	rules = |snapshot| snapshot.rules
	offset : ResolvedBoundary -> FixedOffset
	offset = |snapshot| snapshot.offset

	## Explicitly interpret the original label/policy under another ruleset.
	reresolve : ResolvedBoundary, ZoneRules -> Try(ResolvedBoundary, [Gap, Ambiguous, OffsetConflict, OutsideValidity, OutOfRange, ..])
	reresolve = |snapshot, new_rules| resolve(new_rules, snapshot.source, snapshot.policy)

	## Compare the stored POSIX position, independently of provenance.
	same_position : ResolvedBoundary, ResolvedBoundary -> Bool
	same_position = |a, b| a.boundary == b.boundary

	to_inspect : ResolvedBoundary -> Str
	to_inspect = |snapshot| "ResolvedBoundary(${Str.inspect(snapshot.boundary)}, offset=${Str.inspect(snapshot.offset)}, source=${Str.inspect(snapshot.source)})"
}
