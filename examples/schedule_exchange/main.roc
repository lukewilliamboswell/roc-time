app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0/roc-time-6gt2mALoAXMVKcQvCpdisfaAU3S9XVdV3vR2CNA7e43t.tar.zst",
}
import ScheduleExchange

main! = |_args| {
	for line in ScheduleExchange.render()? {
		echo!("${line}\n")
	}
	Ok({})
}
