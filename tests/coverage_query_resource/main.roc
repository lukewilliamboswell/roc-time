app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.Coverage
import time.PosixBoundary
import QueryFixture

# R04/R15. Measure a late point query and a full overlap fold against a retained
# slice. Verify materialized matches separately, after observing query allocations.
main! = |args| {
	count = U64.from_str(args.get(1) ?? "8") ?? crash "span count"
	matches = U64.from_str(args.get(2) ?? "1") ?? crash "match count"
	control = args.get(3) ?? "normal"
	Host.assert!(count <= 4096 and matches <= count and matches <= 64)
	fixture = QueryFixture.prepare(count, matches)
	before_bytes = Host.allocated_bytes!({})
	before_calls = Host.allocation_count!({})
	point = PosixBoundary.from_microseconds(Host.opaque_u64!(fixture.point.to_u64_wrap()).to_i64_wrap())
	contained = Coverage.contains(fixture.coverage, point)
	folded = Coverage.fold_overlaps(
		fixture.coverage,
		{
			query: fixture.query,
			initial: { count: 0.U64, endpoints: 0.I64 },
			step: QueryFixture.observe,
		},
	)
	if control == "allocate" {
		allocated = List.with_capacity(Host.opaque_u64!(64)).append(matches)
		Host.assert!(allocated.get(0) == Ok(matches))
	}
	bytes = Host.allocated_bytes!({}) - before_bytes
	calls = Host.allocation_count!({}) - before_calls
	Host.assert!(contained == (matches != 0))
	Host.assert!(folded == fixture.expected and bytes == 0 and calls == 0)
	Host.assert!(Coverage.overlapping_spans(fixture.coverage, fixture.query) == fixture.members)
	Host.assert!(fixture.retained.len() == count + 2 and fixture.retained.get(0) == Ok(QueryFixture.span_at(0)))
	{ bytes: "coverage-queries=checked\n".to_utf8(), work: [bytes, calls] }
}
