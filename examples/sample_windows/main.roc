app [main!] {
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc1/roc-time-2T6KR7B59FhCSNghyPAgP2j61YiU1F537CkB6UFUwzfY.tar.zst",
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
