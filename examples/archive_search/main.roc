app [main!] {
	time: "../../package/main.roc",
}
import ArchiveSearch
main! = |_args| {
	# The archive explicitly records UTC. Search precision is supplied by users;
	# the timestamp strings themselves still denote individual instants.
	matches = ArchiveSearch.find({ year: 2025, month: 6, day: 12 }, ["20250612T093000Z", "20250612T093045Z", "20250612T093100Z"])?
	echo!("Archive search (UTC)\n")
	for result in matches {
		echo!("${result.label}: ${result.count.to_str()} recordings\n")
	}
	Ok({})
}
