app [main!] {
	roc: "nightly-2026-09-27-a3ce7f1",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-GPETAiR4TeEPxDA1F6qHxbDnFexmj4tYgUrkEryBhtdP.tar.zst",
}
import InterpretationContext

main! = |_| {
	report = InterpretationContext.review({
		source: "2026-10-03T12:00:00Z[Synthetic/ArchiveAlias][u-ca=hebrew]",
		valid_from: "2026-10-03T00:00:00Z",
		valid_until: "2026-10-04T00:00:00Z",
	})?
	echo!(report)
	Ok({})
}
