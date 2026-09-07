app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc3/roc-time-9gC9GQxjZjAaAPGwaGwSYCGfTuN5ED4AstyM9vdCPe5o.tar.zst",
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
