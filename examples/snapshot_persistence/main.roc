app [main!] {
	time: "../../package/main.roc",
}
import SnapshotArchive

main! = |_| {
	report = SnapshotArchive.restore({
		source: "2026-10-03T12:00:00Z[Synthetic/ArchiveAlias][u-ca=hebrew]",
		valid_from: "2026-10-03T00:00:00Z",
		valid_until: "2026-10-04T00:00:00Z",
	})?
	echo!(report)
	Ok({})
}
