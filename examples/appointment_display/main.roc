app [main!] {
	time: "../../package/main.roc",
}
import AppointmentDisplay

main! = |_args| {
	lines = AppointmentDisplay.describe("2026-09-07T09:30", "2026-09-07T09:30:00.125")?
	for line in lines {
		echo!("${line}\n")
	}
	Ok({})
}
