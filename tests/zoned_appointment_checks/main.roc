app [main!] { time: "../../package/main.roc", zones: "../../tzdb/package/main.roc" }
import AppointmentChecks

main! = |args| {
	AppointmentChecks.run(args.get(1) ?? "Missing/Appointment")?
	echo!("PASS named-zone appointment fixtures\n")
	Ok({})
}
