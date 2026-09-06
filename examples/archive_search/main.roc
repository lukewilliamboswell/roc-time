app [main!] {
	time: "../../package/main.roc",
}
import ArchiveSearch
main! = |_args| {
	# The archive explicitly records UTC. Search precision is supplied by users;
	# the timestamp strings themselves still denote individual instants.
	matches = ArchiveSearch.find({ year: 2025, month: 6, day: 12 }, ["20250612T093000Z", "20250612T093045Z", "20250612T093100Z"], [29, 30, 31])?
	echo!("Archive search (UTC)\n")
	for result in matches {
		match result.outcome {
			Matches(count) => echo!("${result.label}: ${count.to_str()} recordings\n")
			ModelMatches(counts) => echo!("${result.label}: ${counts.possible.to_str()} possible, ${counts.definite.to_str()} definite recordings\n")
			NeedsModel => echo!("${result.label}: no exact count without a search range\n")
		}
	}
	Ok({})
}
