app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.Persistence
import time.Coverage
import time.PosixSpan
import time.PosixBoundary
import PersistenceFixture

# R01/R04/R14/R15. Counters observe allocation request traffic, not retained
# bytes. Input coverage generation and malformed JSON construction are outside
# scopes. Sharing remains observable through equality after parse. No coordinate
# width accumulation is used: the complete signed span exceeds I64 duration.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	count = U32.from_str(args.get(1) ?? "1024") ?? 1024
	ceiling = U64.from_str(args.get(2) ?? "1048576") ?? 1048576
	wide = (args.get(3) ?? "wide") == "wide"
	Host.assert!(count >= 1 and count <= 1024)
	coverage = PersistenceFixture.coverage(count, wide)
	oversized = PersistenceFixture.coverage(1025, wide)
	oversized_json = PersistenceFixture.oversized_json(1025)
	# Runtime switch keeps both signed endpoints as observable input.
	extreme = PersistenceFixture.span(
		if wide {
			I64.lowest
		} else {
			-1
		},
		if wide {
			I64.highest
		} else {
			1
		},
	)
	before = Host.allocated_bytes!({})
	value = match Persistence.new(Coverage(coverage)) {
		Ok(v) => v
		Err(_) => crash "coverage persistence construction"
	}
	constructed = Host.allocated_bytes!({})
	Host.assert!(constructed == before)
	text = Persistence.to_text(value)
	serialized = Host.allocated_bytes!({})
	Host.assert!(serialized - constructed <= ceiling)
	parsed = match Persistence.parse(text) {
		Ok(v) => v
		Err(_) => crash "coverage persistence parsing"
	}
	decoded = Host.allocated_bytes!({})
	Host.assert!(decoded - serialized <= ceiling and Persistence.value(parsed) == Coverage(coverage) and Coverage.member_count(coverage) == count.to_u64())
	span_value = match Persistence.new(PosixSpan(extreme)) {
		Ok(v) => v
		Err(_) => crash "span persistence construction"
	}
	span_before = Host.allocated_bytes!({})
	span_text = Persistence.to_text(span_value)
	span_serialized = Host.allocated_bytes!({})
	span_parsed = match Persistence.parse(span_text) {
		Ok(v) => v
		Err(_) => crash "span persistence parsing"
	}
	span_decoded = Host.allocated_bytes!({})
	Host.assert!(Persistence.value(span_parsed) == PosixSpan(extreme) and span_serialized - span_before <= ceiling and span_decoded - span_serialized <= ceiling)
	Host.assert!(
		PosixSpan.start(extreme) == PosixBoundary.from_microseconds(
			if wide {
				I64.lowest
			} else {
				-1
			},
		) and PosixSpan.end(extreme) == PosixBoundary.from_microseconds(
			if wide {
				I64.highest
			} else {
				1
			},
		),
	)
	reject_before = Host.allocated_bytes!({})
	rejected = Persistence.new(Coverage(oversized))
	reject_after = Host.allocated_bytes!({})
	Host.assert!(rejected == Err(TooManyMembers) and reject_after == reject_before)
	parsed_rejection = Persistence.parse(oversized_json)
	parse_rejected = Host.allocated_bytes!({})
	Host.assert!(parsed_rejection == Err(TooManyMembers) and parse_rejected - reject_after <= ceiling)
	{ bytes: "coverage=preserved,span=preserved,1025=rejected\n".to_utf8(), work: [constructed - before, serialized - constructed, decoded - serialized, span_serialized - span_before, span_decoded - span_serialized, reject_after - reject_before, parse_rejected - reject_after] }
}
