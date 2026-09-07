app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.Explanation
import time.Ixdtf
import time.SemanticFact
import time.PosixBoundary
import ExplanationFixture

# R09/R15/R16: retained provider tables and metadata are runtime inputs outside
# measured scopes. Rendering must use bound facts without scanning transitions
# or copying the full 1MiB version field. Counts are allocation traffic, not
# retained memory; source snapshots intentionally retain their supplied rules.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	count = U32.from_str(args.get(1) ?? "16384") ?? 16384
	text_size = U32.from_str(args.get(2) ?? "524288") ?? 524288
	ceiling = U64.from_str(args.get(3) ?? "65536") ?? 65536
	source_text = args.get(4) ?? "1970-01-01T00:00:01Z[Fixture/Explanation][u-ca=hebrew]"
	Host.assert!(count >= 2 and count <= 16384 and U32.rem_by(count, 2) == 0 and (text_size == 4 or text_size == 524288))
	rules = ExplanationFixture.rules(count, text_size)
	source = match Ixdtf.parse(source_text) {
		Ok(v) => v
		Err(_) => crash "fixture source"
	}
	snapshot = match Ixdtf.resolve(source, Some(rules)) {
		Ok(v) => v
		Err(_) => crash "fixture snapshot"
	}
	# Fact reads remain independent of retained provider size. Presentation
	# preference may inspect at most 32 source annotations, never zone rules.
	facts_before = Host.allocated_bytes!({})
	var $reads = 0.U32
	while $reads < 100000 {
		match Ixdtf.Snapshot.fact_at(snapshot, 0) {
			Item(fact) => match SemanticFact.kind(fact) {
				ResolvedPosition(position) => Host.assert!(position.boundary == PosixBoundary.from_microseconds(1000000))
				_ => Host.assert!(False)
			}
			End => Host.assert!(False)
		}
		match Ixdtf.Snapshot.fact_at(snapshot, 1) {
			Item(fact) => match SemanticFact.kind(fact) {
				Presentation(UnsupportedCalendar(name)) => Host.assert!(name == "hebrew")
				_ => Host.assert!(False)
			}
			End => Host.assert!(False)
		}
		$reads = $reads + 1
	}
	facts_after = Host.allocated_bytes!({})
	Host.assert!(facts_after == facts_before)
	before = Host.allocated_bytes!({})
	explanation = Explanation.new(Snapshot(snapshot))
	constructed = Host.allocated_bytes!({})
	zero = Explanation.plain(explanation, { max_facts: 0, max_utf8_bytes: 65536 })
	zero_facts = Host.allocated_bytes!({})
	empty = Explanation.plain(explanation, { max_facts: 100, max_utf8_bytes: 0 })
	zero_bytes = Host.allocated_bytes!({})
	Host.assert!(constructed == before and zero_facts == constructed and zero_bytes == zero_facts and zero.visited_facts == 0 and empty.visited_facts == 0 and zero.text == "" and empty.text == "" and zero.status == Limited(FactLimit) and empty.status == Limited(ByteLimit))
	tiny = Explanation.plain(explanation, { max_facts: 1, max_utf8_bytes: 4 })
	tiny_after = Host.allocated_bytes!({})
	Host.assert!(tiny_after - zero_bytes <= ceiling and tiny.visited_facts == 1 and tiny.text.count_utf8_bytes() <= 4 and tiny.text.ends_with("...") and tiny.status == Limited(ByteLimit))
	full = Explanation.plain(explanation, { max_facts: 100, max_utf8_bytes: 65536 })
	full_after = Host.allocated_bytes!({})
	Host.assert!(full_after - tiny_after <= ceiling and full.visited_facts == full.total_facts and full.text.count_utf8_bytes() < 4096)
	Host.assert!(full.text.contains("Resolved instant") and full.text.contains("hebrew") and full.text.contains("unsupported") and full.text.contains("resolved instant remains known"))
	Host.assert!(
		full.status == (
			if text_size == 4 {
				Complete
			} else {
				Limited(TextLimit)
			}
		),
	)
	if text_size != 4 {
		Host.assert!(full.text.contains("..."))
	}
	summary_before = Host.allocated_bytes!({})
	summary = Str.inspect(snapshot)
	summary_after = Host.allocated_bytes!({})
	Host.assert!(summary.count_utf8_bytes() <= 256 and summary_after - summary_before <= ceiling)
	Host.assert!(Ixdtf.Snapshot.boundary(snapshot) == PosixBoundary.from_microseconds(1000000))
	match Explanation.fact_at(explanation, 0) {
		Item(fact) => match SemanticFact.kind(fact) {
			ResolvedPosition(position) => Host.assert!(position.boundary == PosixBoundary.from_microseconds(1000000))
			_ => Host.assert!(False)
		}
		End => Host.assert!(False)
	}
	{ bytes: "render=bounded,instant=known,presentation=unsupported\n".to_utf8(), work: [constructed - before, zero_facts - constructed, zero_bytes - zero_facts, tiny_after - zero_bytes, full_after - tiny_after, summary_after - summary_before, facts_after - facts_before] }
}
