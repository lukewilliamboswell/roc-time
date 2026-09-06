app [main!] {
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc1/roc-time-2T6KR7B59FhCSNghyPAgP2j61YiU1F537CkB6UFUwzfY.tar.zst",
}
import ArchiveSearch
main! = |_args| {
	# The archive searches in UTC; recordings carry explicit offsets. Search precision is supplied by users;
	# the timestamp strings themselves still denote individual instants.
	matches = ArchiveSearch.find({ year: 2025, month: 6, day: 12 }, ["2025-06-12T09:30:00Z", "2025-06-12T11:30:45+02:00", "2025-06-12T09:31:00Z"], [29, 30, 31])?
	echo!("Archive search (UTC)\n")
	for result in matches {
		match result.outcome {
			Matches(count) => echo!("${result.label}: ${count.to_str()} recordings\n")
			ModelMatches(counts) => echo!("${result.label}: ${counts.possible.to_str()} possible, ${counts.definite.to_str()} definite recordings\n")
			NeedsModel => echo!("${result.label}: no exact count without a search range\n")
		}
	}
	imported = ArchiveSearch.import_dates(["2025", "2025-06", "2025-06-12", "2025-06~"], ["2025-06-12T09:30:00Z", "2025-06-13T09:30:00Z", "2025-07-01T09:30:00Z"])?
	echo!("Imported archive dates (UTC)\n")
	for result in imported {
		match result.outcome {
			Matches(count) => echo!("${result.label}: ${count.to_str()} recordings\n")
			NeedsModel => echo!("${result.label}: preserved; needs an explicit model\n")
		}
	}
	Ok({})
}
