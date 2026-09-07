app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.Ixdtf
import time.Persistence
import time.ExactInterval
import time.PosixBoundary
import time.PosixSpan
import time.LocalDateTime
import time.ClockTime
import time.FixedOffset
import time.ZoneRules
import time.EdtfDate
import time.Explanation
import time.SemanticFact
import InterchangeFixture

# R09/R14/R15: runtime text and rules; counters measure requested allocation
# traffic, not live/retained bytes. Provider creation is outside the scopes.
# Resolve scans the explicit transition table once; stored presentation/getters
# must not pay that cost repeatedly. Every observed result reaches hosted asserts.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	count = U32.from_str(args.get(1) ?? "16384") ?? 16384
	tags = U32.from_str(args.get(2) ?? "32") ?? 32
	ceiling = U64.from_str(args.get(3) ?? "4194304") ?? 4194304
	Host.assert!(count >= 2 and count <= 16384 and U32.rem_by(count, 2) == 0 and tags >= 1 and tags <= 32)
	rules = InterchangeFixture.rules(count)
	text = InterchangeFixture.text(tags)
	before = Host.allocated_bytes!({})
	declaration = match Ixdtf.parse(text) {
		Ok(v) => v
		Err(_) => crash "parse fixture"
	}
	parsed = Host.allocated_bytes!({})
	Host.assert!(parsed - before <= ceiling)
	canonical = Ixdtf.to_text(declaration)
	serialized = Host.allocated_bytes!({})
	Host.assert!(canonical == text and serialized - parsed <= ceiling)
	snapshot = match Ixdtf.resolve(declaration, Some(rules)) {
		Ok(v) => v
		Err(_) => crash "resolve fixture"
	}
	resolved = Host.allocated_bytes!({})
	Host.assert!(resolved - serialized <= ceiling)
	Host.mark!(1)
	var $i = 0.U32
	while $i < 100000 {
		local = match Ixdtf.Snapshot.presentation(snapshot) {
			Ok(v) => v
			Err(_) => crash "stored presentation"
		}
		Host.assert!(ClockTime.to_microseconds_since_midnight(LocalDateTime.clock(local)) == 1000000 and Ixdtf.Snapshot.boundary(snapshot) == PosixBoundary.from_microseconds(1000000) and Ixdtf.Snapshot.offset(snapshot) == FixedOffset.from_seconds(0))
		$i = $i + 1
	}
	queried = Host.allocated_bytes!({})
	Host.assert!(queried == resolved)
	Host.mark!(2)
	summary = Str.inspect(snapshot)
	declaration_summary = Str.inspect(declaration)
	inspected = Host.allocated_bytes!({})
	Host.assert!(summary.count_utf8_bytes() < 160 and declaration_summary.count_utf8_bytes() < 160 and inspected - queried <= ceiling)
	Host.assert!(Ixdtf.Snapshot.source(snapshot) == declaration)
	match Ixdtf.Snapshot.context(snapshot) {
		Some(retained) => Host.assert!(ZoneRules.name(retained) == "Fixture/Many" and ZoneRules.version(retained) == "resource-v1")
		None => Host.assert!(False)
	}
	exact_text = args.get(4) ?? "1970-01-01T01:00:00+01:00/1970-01-01T00:00:02Z"
	exact_before = Host.allocated_bytes!({})
	exact = match ExactInterval.parse(exact_text) {
		Ok(v) => v
		Err(_) => crash "exact fixture"
	}
	exact_parsed = Host.allocated_bytes!({})
	Host.assert!(PosixSpan.start(ExactInterval.span(exact)) == PosixBoundary.from_microseconds(0) and PosixSpan.end(ExactInterval.span(exact)) == PosixBoundary.from_microseconds(2000000) and exact_parsed - exact_before <= ceiling)
	exact_output = ExactInterval.to_text(exact)
	exact_serialized = Host.allocated_bytes!({})
	Host.assert!(exact_output == exact_text and exact_serialized - exact_parsed <= ceiling)
	# Persist the declaration; the rule snapshot must be rebound explicitly.
	saved = match Persistence.new(Ixdtf(declaration)) {
		Ok(value) => value
		Err(_) => crash "bounded declaration persistence"
	}
	persistence_before = Host.allocated_bytes!({})
	encoded = Persistence.to_text(saved)
	persistence_encoded = Host.allocated_bytes!({})
	Host.assert!(persistence_encoded - persistence_before <= ceiling)
	decoded = match Persistence.parse(encoded) {
		Ok(v) => v
		Err(_) => crash "persistence fixture"
	}
	persistence_decoded = Host.allocated_bytes!({})
	Host.assert!(Persistence.value(decoded) == Ixdtf(declaration) and persistence_decoded - persistence_encoded <= ceiling)
	oversized = " ".repeat(65537)
	deep_unknown = "{\"unknown\":${"[".repeat(10000)}"
	invalid_before = Host.allocated_bytes!({})
	large_result = Persistence.parse(oversized)
	invalid_large = Host.allocated_bytes!({})
	Host.assert!(large_result == Err(Envelope(TooLarge)) and invalid_large == invalid_before)
	deep_result = Persistence.parse(deep_unknown)
	invalid_deep = Host.allocated_bytes!({})
	Host.assert!(deep_result == Err(Envelope(UnknownField("unknown"))) and invalid_deep - invalid_large <= ceiling)

	# Five distinct scopes exercise the profile's full qualification capacity.
	# Runtime input and oversized-input construction precede the measured scopes.
	edtf_text = args.get(5) ?? "?2004-%06~-~11?"
	edtf_ceiling = U64.from_str(args.get(6) ?? "16384") ?? 16384
	edtf_oversized = edtf_text.repeat(5)
	Host.assert!(edtf_oversized.count_utf8_bytes() > 64)
	Host.mark!(3)
	edtf_before = Host.allocated_bytes!({})
	edtf = match EdtfDate.parse(edtf_text) {
		Ok(value) => value
		Err(_) => crash "scoped EDTF fixture"
	}
	edtf_parsed = Host.allocated_bytes!({})
	Host.assert!(edtf_parsed - edtf_before <= edtf_ceiling and EdtfDate.fact_count(edtf) == 8)
	Host.assert!(EdtfDate.fact_at(edtf, 7) == Item(SemanticFact.new(Qualification({ scope: YearMonth, qualifier: Approximate }))))
	edtf_output = EdtfDate.to_text(edtf)
	edtf_serialized = Host.allocated_bytes!({})
	Host.assert!(edtf_output == edtf_text and edtf_serialized - edtf_parsed <= edtf_ceiling)
	explanation = Explanation.new(EdtfDate(edtf))
	report = Explanation.plain(explanation, { max_facts: 8, max_utf8_bytes: 1024 })
	tiny = Explanation.plain(explanation, { max_facts: 1, max_utf8_bytes: 3 })
	edtf_explained = Host.allocated_bytes!({})
	Host.assert!(edtf_explained - edtf_serialized <= edtf_ceiling and report.status == Complete and report.visited_facts == 8 and report.text.count_utf8_bytes() <= 1024 and report.text.contains("YearMonth"))
	Host.assert!(tiny.status == Limited(ByteLimit) and tiny.visited_facts == 1 and tiny.text == "...")
	edtf_invalid_before = Host.allocated_bytes!({})
	edtf_invalid = EdtfDate.parse(edtf_oversized)
	edtf_rejected = Host.allocated_bytes!({})
	Host.assert!(edtf_invalid == Err(TooLarge) and edtf_rejected == edtf_invalid_before)
	Host.mark!(4)
	{ bytes: "instant=1000000,presentation=1000000,exact=0..2000000,edtf=scopes-preserved\n".to_utf8(), work: [parsed - before, serialized - parsed, resolved - serialized, queried - resolved, inspected - queried, exact_parsed - exact_before, exact_serialized - exact_parsed, persistence_encoded - persistence_before, persistence_decoded - persistence_encoded, invalid_large - invalid_before, invalid_deep - invalid_large, edtf_parsed - edtf_before, edtf_serialized - edtf_parsed, edtf_explained - edtf_serialized, edtf_rejected - edtf_invalid_before] }
}
