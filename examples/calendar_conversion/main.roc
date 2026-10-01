app [main!] {
	roc: "nightly-2026-09-27-a3ce7f1",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-GPETAiR4TeEPxDA1F6qHxbDnFexmj4tYgUrkEryBhtdP.tar.zst",
}
import ArchiveDate

main! = |_args| {
	# The archive explicitly identifies its source calendar. No reform date or
	# country is inferred from the numerical year on the record.
	entry = ArchiveDate.from_record("julian", { year: 1582, month: 10, day: 5 })?
	echo!(ArchiveDate.report(entry))
	Ok({})
}
