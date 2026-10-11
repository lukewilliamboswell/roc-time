app [main!] {
	roc: "nightly-2026-09-27-a3ce7f1",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-GPETAiR4TeEPxDA1F6qHxbDnFexmj4tYgUrkEryBhtdP.tar.zst",
}

import SampleWindow

main! = |_args| {
	# A recorder supplied exact POSIX seconds for two successive sample windows.
	first = SampleWindow.from_seconds(0.000001.Dec, 0.000002.Dec)?
	next = SampleWindow.from_seconds(0.000002.Dec, 0.000003.Dec)?
	echo!("Recorder handoff at 0.000002 POSIX seconds\n")
	echo!("${SampleWindow.handoff_report(first, next)}\n")
	Ok({})
}
