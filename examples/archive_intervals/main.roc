app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	time: "../../package/main.roc",
}

import cli.Stdout
import ArchiveInterval

main! = |_args| {
	for (accession, source) in [("painting-17", "1964/2008"), ("letters-42", "2004-02-01/2005-02"), ("collection-9", "1985/"), ("ongoing-6", "1985/.."), ("draft-2", "2004-06-~01/2004-06-~20")] {
		record = ArchiveInterval.import_record(accession, source)?
		Stdout.line!(ArchiveInterval.export_record(record))?
	}
	request = ArchiveInterval.import_record("letters-42", "2004-02-01/2005-02")?
	Stdout.line!(ArchiveInterval.query_status(request))
}
