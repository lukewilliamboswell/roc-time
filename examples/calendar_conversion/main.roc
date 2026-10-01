app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0/roc-time-6gt2mALoAXMVKcQvCpdisfaAU3S9XVdV3vR2CNA7e43t.tar.zst",
}
import ArchiveDate

main! = |_args| {
	# The archive explicitly identifies its source calendar. No reform date or
	# country is inferred from the numerical year on the record.
	entry = ArchiveDate.from_record("julian", { year: 1582, month: 10, day: 5 })?
	echo!(ArchiveDate.report(entry))
	Ok({})
}
