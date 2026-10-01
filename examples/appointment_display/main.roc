app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0/roc-time-6gt2mALoAXMVKcQvCpdisfaAU3S9XVdV3vR2CNA7e43t.tar.zst",
}
import AppointmentDisplay

main! = |_args| {
	lines = AppointmentDisplay.describe("2026-09-07T09:30", "2026-09-07T09:30:00.125")?
	for line in lines {
		echo!("${line}\n")
	}
	Ok({})
}
