app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.Explanation
import time.SemanticFact
import time.Coverage
import time.PosixSpan
import time.PosixBoundary
import time.FixedOffset
import time.ZoneRules
import time.ResolvedBoundary
import time.ResolvedSelection
import SelectionFixture

# R07/R09/R15/R16: input construction precedes counters. The runtime matrix
# varies actual retained spans/transitions and UTF8 metadata. Counters measure
# cumulative allocation requests, not retained/live memory. Fixed fact budgets
# must not enumerate the rest of the source or traverse its provider table.
main! = |args| {
	count = U32.from_str(args.get(1) ?? "16384") ?? 16384
	text_size = U32.from_str(args.get(2) ?? "524288") ?? 524288
	kind = args.get(3) ?? "batch"
	ownership = args.get(4) ?? "shared"
	ceiling = U64.from_str(args.get(5) ?? "65536") ?? 65536
	Host.assert!(count == 2 or count == 16384)
	Host.assert!(text_size == 4 or text_size == 524288)
	coverage = SelectionFixture.coverage(count, ownership)
	rules = SelectionFixture.rules(count, text_size)
	start = match FixedOffset.project(FixedOffset.from_seconds(0), PosixBoundary.from_microseconds(count.to_i64() - count.to_i64()), Gregorian) {
		Ok(v) => v
		Err(_) => crash "start"
	}
	end = match FixedOffset.project(FixedOffset.from_seconds(0), PosixBoundary.from_microseconds(4000000000000000000 - count.to_i64()), Julian) {
		Ok(v) => v
		Err(_) => crash "end"
	}
	boundary = match ResolvedBoundary.resolve(rules, start, RequireUnique) {
		Ok(v) => v
		Err(_) => crash "boundary"
	}
	selection = match ResolvedSelection.resolve(rules, start, end) {
		Ok(v) => v
		Err(_) => crash "selection"
	}
	cursor = match ZoneRules.selection_cursor(rules, start, end) {
		Ok(v) => v
		Err(_) => crash "cursor"
	}
	batch = match ResolvedSelection.collect(cursor, { max_segments: 1, max_members: 1 }) {
		Ok(v) => v
		Err(_) => crash "batch"
	}
	source = match kind {
		"coverage" => Coverage(coverage.value)
		"boundary" => ResolvedBoundary(boundary)
		"selection" => ResolvedSelection(selection)
		_ => SelectionBatch(batch)
	}
	before = Host.allocated_bytes!({})
	explanation = Explanation.new(source)
	constructed = Host.allocated_bytes!({})
	var $i = 0.U32
	while $i < 100000 {
		match Explanation.fact_at(explanation, 0) {
			Item(fact) => Host.assert!(
				match SemanticFact.kind(fact) {
					CoverageDescription(data) => kind == "coverage" and data.member_count == count.to_u64()
					CivilBoundaryDescription(data) => kind == "boundary" and data.boundary == PosixBoundary.from_microseconds(0) and data.policy == RequireUnique
					CivilSelectionDescription(data) => kind == "selection" and data.member_count == 1 and data.start == start and data.end == end
					SelectionEvaluation(data) => kind == "batch" and data.status == Limited(WorkLimit) and data.segments == 1 and data.buffered == 0
					_ => False
				},
			)
			End => Host.assert!(False)
		}
		match Explanation.fact_at(
			explanation,
			if kind == "batch" {
				2
			} else {
				1
			},
		) {
			Item(fact) => Host.assert!(
				match SemanticFact.kind(fact) {
					CoverageMember(data) => kind == "coverage" and data.index == 0 and PosixBoundary.to_microseconds(PosixSpan.start(data.span)) == (
						if ownership == "sliced" {
							2
						} else {
							0
						}
					)
					Context(data) => kind != "coverage" and data.name == "Fixture/Selection" and data.version.count_utf8_bytes() == text_size.to_u64() * 2
					_ => False
				},
			)
			End => Host.assert!(False)
		}
		$i = $i + 1
	}
	read = Host.allocated_bytes!({})
	zero = Explanation.plain(explanation, { max_facts: 0, max_utf8_bytes: 4096 })
	empty = Explanation.plain(explanation, { max_facts: 4, max_utf8_bytes: 0 })
	zero_after = Host.allocated_bytes!({})
	Host.assert!(constructed == before and read == constructed and zero_after == read)
	Host.assert!(zero.visited_facts == 0 and empty.visited_facts == 0 and zero.text == "" and empty.text == "" and zero.status == Limited(FactLimit) and empty.status == Limited(ByteLimit))
	tiny = Explanation.plain(explanation, { max_facts: 1, max_utf8_bytes: 4 })
	tiny_after = Host.allocated_bytes!({})
	Host.assert!(tiny.visited_facts == 1 and tiny.text.count_utf8_bytes() <= 4 and tiny.status == Limited(ByteLimit) and tiny_after - zero_after <= ceiling)
	fixed = Explanation.plain(explanation, { max_facts: 3, max_utf8_bytes: 4096 })
	fixed_after = Host.allocated_bytes!({})
	Host.assert!(fixed.visited_facts <= 3 and fixed.text.count_utf8_bytes() <= 4096 and fixed_after - tiny_after <= ceiling)
	if kind == "batch" {
		Host.assert!(fixed.visited_facts == 3 and fixed.text.contains("incomplete"))
		Host.assert!(
			fixed.status == (
				if text_size == 4 {
					Complete
				} else {
					Limited(TextLimit)
				}
			),
		)
	}
	summary = match source {
		Coverage(v) => Str.inspect(v)
		ResolvedBoundary(v) => Str.inspect(v)
		ResolvedSelection(v) => Str.inspect(v)
		SelectionBatch(_) => Str.inspect(explanation)
		_ => crash "fixture source"
	}
	inspected = Host.allocated_bytes!({})
	Host.assert!(summary.count_utf8_bytes() <= 256 and inspected - fixed_after <= ceiling)
	Host.assert!(Coverage.member_count(coverage.value) == count.to_u64())
	match coverage.retained {
		Some(spans) => {
			Host.assert!(spans.len() == count.to_u64() + 2)
			match spans.get(0) {
				Ok(span) => Host.assert!(PosixSpan.start(span) == PosixBoundary.from_microseconds(0))
				Err(_) => Host.assert!(False)
			}
			match spans.get(count.to_u64() + 1) {
				Ok(span) => Host.assert!(PosixSpan.end(span) == PosixBoundary.from_microseconds(count.to_i64() * 2 + 3))
				Err(_) => Host.assert!(False)
			}
		}
		None => {}
	}
	Host.assert!(ResolvedBoundary.boundary(boundary) == PosixBoundary.from_microseconds(0))
	{ bytes: "selection=facts-bounded,incompleteness-preserved\n".to_utf8(), work: [constructed - before, read - constructed, zero_after - read, tiny_after - zero_after, fixed_after - tiny_after, inspected - fixed_after] }
}
