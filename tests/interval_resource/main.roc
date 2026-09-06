app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.IntervalEvidence
import time.PosixBoundary
import time.PosixSpan
import IntervalFixture

# Counters observe cumulative requested bytes, not live or retained memory.
# Runtime inputs are outside construction scopes. Shared/sliced backing is
# consumed after queries so normalization cannot silently gain sole ownership.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	n = U32.from_str(args.get(1) ?? "4096") ?? 4096
	ceiling = U64.from_str(args.get(2) ?? "4194304") ?? 4194304
	ownership = args.get(3) ?? "owned"
	Host.assert!(n >= 2 and n <= 4096)
	backing = IntervalFixture.inputs(
		if ownership == "sliced" {
			n + 2
		} else {
			n
		},
	)
	inputs = if ownership == "sliced" {
		IntervalFixture.sliced(backing, n)
	} else {
		backing
	}
	retained = if ownership == "owned" {
		None
	} else {
		Some(backing)
	}
	before = Host.allocated_bytes!({})
	independent = match IntervalEvidence.independent({ starts: inputs.starts, ends: inputs.ends }) {
		Ok(value) => value
		Err(_) => crash "independent construction"
	}
	constructed = Host.allocated_bytes!({})
	Host.assert!(constructed - before <= ceiling)
	Host.mark!(1)
	shift = if ownership == "sliced" {
		1.I64
	} else {
		0.I64
	}
	zero = IntervalEvidence.contains(independent, PosixBoundary.from_microseconds(0))
	edge = IntervalEvidence.contains(independent, PosixBoundary.from_microseconds(-n.to_i64() - shift))
	outside = IntervalEvidence.contains(independent, PosixBoundary.from_microseconds(n.to_i64() + shift))
	queried = Host.allocated_bytes!({})
	Host.assert!(zero == Definite and edge == Possible and outside == Impossible)
	Host.assert!(queried == constructed)
	Host.mark!(2)
	paired_before = Host.allocated_bytes!({})
	paired = match IntervalEvidence.paired(inputs.spans) {
		Ok(value) => value
		Err(_) => crash "paired construction"
	}
	paired_constructed = Host.allocated_bytes!({})
	Host.assert!(paired_constructed - paired_before <= ceiling)
	first = IntervalEvidence.contains(paired, PosixBoundary.from_microseconds(shift * 3))
	gap = IntervalEvidence.contains(paired, PosixBoundary.from_microseconds(shift * 3 + 1))
	paired_queried = Host.allocated_bytes!({})
	Host.assert!(first == Possible and gap == Impossible and paired_queried == paired_constructed)
	match IntervalEvidence.declaration(independent) {
		Independent(values) => Host.assert!(values.starts.len() == n.to_u64() and values.ends.len() == n.to_u64())
		_ => Host.assert!(False)
	}
	match IntervalEvidence.declaration(paired) {
		Paired(values) => Host.assert!(values.len() == n.to_u64())
		_ => Host.assert!(False)
	}
	match retained {
		None => {}
		Some(original) => {
			expected_length = if ownership == "sliced" {
				(n + 2).to_u64()
			} else {
				n.to_u64()
			}
			Host.assert!(original.starts.len() == expected_length and original.starts.first() == Ok(PosixBoundary.from_microseconds(-1)))
			Host.assert!(original.ends.len() == expected_length and original.ends.first() == Ok(PosixBoundary.from_microseconds(1)))
			Host.assert!(original.spans.len() == expected_length)
			match original.spans.first() {
				Ok(span) => Host.assert!(PosixSpan.start(span) == PosixBoundary.from_microseconds(0) and PosixSpan.end(span) == PosixBoundary.from_microseconds(1))
				Err(_) => Host.assert!(False)
			}
		}
	}
	{ bytes: "independent=definite,edge=possible,outside=impossible,paired-gap=impossible\n".to_utf8(), work: [constructed - before, queried - constructed, paired_constructed - paired_before, paired_queried - paired_constructed] }
}
