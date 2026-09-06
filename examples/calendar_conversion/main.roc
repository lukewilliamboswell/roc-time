app [main!] {
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc1/roc-time-2T6KR7B59FhCSNghyPAgP2j61YiU1F537CkB6UFUwzfY.tar.zst",
}
import ArchiveDate

main! = |_args| {
	# The archive explicitly identifies its source calendar. No reform date or
	# country is inferred from the numerical year on the record.
	entry = ArchiveDate.from_record("julian", { year: 1582, month: 10, day: 5 })?
	echo!(ArchiveDate.report(entry))
	Ok({})
}
