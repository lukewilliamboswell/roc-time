app [main!] {
	roc: "nightly-2026-09-27-a3ce7f1",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-GPETAiR4TeEPxDA1F6qHxbDnFexmj4tYgUrkEryBhtdP.tar.zst",
}
import EvidenceReview
main! = |_args| {
	# One incident has two candidate reports. In the first model, each report's
	# start and end belong together. The second model has only independent notes.
	paired = [
		{ start: "20250612T120000Z", end: "20250612T120500Z" },
		{ start: "20250612T121000Z", end: "20250612T121500Z" },
	]
	independent = { starts: ["20250612T120000Z", "20250612T121000Z"], ends: ["20250612T120500Z", "20250612T121500Z"] }
	probes = [{ label: "12:02 UTC", time: "20250612T120200Z" }, { label: "12:07 UTC", time: "20250612T120700Z" }, { label: "12:15 UTC", time: "20250612T121500Z" }]
	results = EvidenceReview.compare(paired, independent, probes)?
	echo!("Possible outage intervals\n")
	for result in results {
		echo!("${result.label}: paired ${result.paired}, independent ${result.independent}\n")
	}
	Ok({})
}
