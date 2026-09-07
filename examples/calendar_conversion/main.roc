app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc3/roc-time-9gC9GQxjZjAaAPGwaGwSYCGfTuN5ED4AstyM9vdCPe5o.tar.zst",
}
import ArchiveDate

main! = |_args| {
	# The archive explicitly identifies its source calendar. No reform date or
	# country is inferred from the numerical year on the record.
	entry = ArchiveDate.from_record("julian", { year: 1582, month: 10, day: 5 })?
	echo!(ArchiveDate.report(entry))
	Ok({})
}
