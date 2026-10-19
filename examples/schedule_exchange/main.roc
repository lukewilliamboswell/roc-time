app [main!] {
	time: "../../package/main.roc",
}
import ScheduleExchange

main! = |_args| {
	for line in ScheduleExchange.render()? {
		echo!("${line}\n")
	}
	Ok({})
}
