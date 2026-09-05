app [main!] {
	time: "../../package/main.roc",
}
import ArchiveDate

main! = |_args| {
	# The archive explicitly identifies its source calendar. No reform date or
	# country is inferred from the numerical year on the record.
	entry = ArchiveDate.from_record("julian", { year: 1582, month: 10, day: 5 })?
	echo!(ArchiveDate.report(entry))
	Ok({})
}
