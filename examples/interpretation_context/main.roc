app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0/roc-time-6gt2mALoAXMVKcQvCpdisfaAU3S9XVdV3vR2CNA7e43t.tar.zst",
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
