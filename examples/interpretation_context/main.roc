app [main!] {
	time: "../../package/main.roc",
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
