import SemanticFact
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

	## Choose an occurrence under explicit rules and policy, retaining the inputs
	## and actual offset. Reject gaps, unresolved ambiguity, offset conflicts,
	## and labels whose interpretation exceeds the rules or numeric range.
	resolve : ZoneRules, LocalDateTime, ZoneRules.OccurrencePolicy -> Try(ResolvedBoundary, [Gap, Ambiguous, OffsetConflict, OutsideValidity, OutOfRange, ..])
	resolve = |rules, source, policy| {
		boundary = ZoneRules.resolve_occurrence(rules, source, policy)?
		offset = ZoneRules.offset_at(rules, boundary)?
		Ok({ source, policy, rules, boundary, offset })
	}

	## Return the stored resolved POSIX coordinate without reinterpreting the source.
	boundary : ResolvedBoundary -> PosixBoundary
	boundary = |snapshot| snapshot.boundary

	## Return the original civil label, including its calendar.
	source : ResolvedBoundary -> LocalDateTime
	source = |snapshot| snapshot.source

	## Return the occurrence-selection policy used for this result.
	policy : ResolvedBoundary -> ZoneRules.OccurrencePolicy
	policy = |snapshot| snapshot.policy

	## Return the exact immutable rules retained by this result.
	rules : ResolvedBoundary -> ZoneRules
	rules = |snapshot| snapshot.rules

	## Return the actual offset at the chosen occurrence.
	offset : ResolvedBoundary -> FixedOffset
	offset = |snapshot| snapshot.offset

	## Explicitly interpret the original label/policy under another ruleset.
	reresolve : ResolvedBoundary, ZoneRules -> Try(ResolvedBoundary, [Gap, Ambiguous, OffsetConflict, OutsideValidity, OutOfRange, ..])
	reresolve = |snapshot, new_rules| resolve(new_rules, snapshot.source, snapshot.policy)

	## Compare the stored POSIX position, independently of provenance.
	same_position : ResolvedBoundary, ResolvedBoundary -> Bool
	same_position = |a, b| a.boundary == b.boundary

	## Description/evidence identity includes policy and complete retained rules.
	## Use same_position to compare only the resulting POSIX coordinate.
	is_eq : ResolvedBoundary, ResolvedBoundary -> Bool
	is_eq = |a, b| a.source == b.source and a.policy == b.policy and a.boundary == b.boundary and a.offset == b.offset and ZoneRules.definition(a.rules) == ZoneRules.definition(b.rules)

	## Hash the source, policy, result and complete rules consistently with is_eq.
	## Work includes the retained transition table; this is not a position-only hash.
	to_hash : ResolvedBoundary, Hasher -> Hasher
	to_hash = |value, hasher| ZoneRules.definition(value.rules).to_hash(value.offset.to_hash(value.boundary.to_hash(value.policy.to_hash(value.source.to_hash(hasher)))))

	## Facts read only stored source, policy, result and context metadata.
	fact_count : ResolvedBoundary -> U64
	fact_count = |_| 2

	## Read the stored result at index zero or context metadata at index one;
	## return End otherwise. No zone lookup or transition traversal occurs.
	fact_at : ResolvedBoundary, U64 -> [End, Item(SemanticFact)]
	fact_at = |snapshot, index| match index {
		0 => Item(SemanticFact.new(CivilBoundaryDescription({ source: snapshot.source, policy: snapshot.policy, boundary: snapshot.boundary, offset: snapshot.offset })))
		1 => Item(SemanticFact.new(Context({ name: ZoneRules.name(snapshot.rules), version: ZoneRules.version(snapshot.rules), validity: ZoneRules.validity(snapshot.rules), provenance: ZoneRules.provenance(snapshot.rules) })))
		_ => End
	}

	## Summarize the source, policy and stored result without re-resolving it.
	to_inspect : ResolvedBoundary -> Str
	to_inspect = |snapshot| match fact_at(snapshot, 0) {
		Item(fact) => SemanticFact.summary(fact)
		End => crash "Resolved boundary always supplies its summary fact"
	}
}
