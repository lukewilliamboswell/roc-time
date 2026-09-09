app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0/roc-time-6gt2mALoAXMVKcQvCpdisfaAU3S9XVdV3vR2CNA7e43t.tar.zst",
	zones: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0/roc-time-tzdb-3JTmpDV26cHNH7cN1HqHzUWTZKpyaYgLYkWSws8Tqj3e.tar.zst",
}
import MeetingExchange

main! = |_args| {
	for line in MeetingExchange.render()? {
		echo!("${line}\n")
	}
	Ok({})
}
