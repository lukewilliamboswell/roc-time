app [main!] {
	time: "../../package/main.roc",
}
import ReservationPlan
main! = |_args| {
	# Extracted RDATE PERIOD values: extend the first reservation overnight,
	# and add another after the two-start daily series has finished.
	periods = ["19970101T180000Z/19970102T070000Z", "19970103T180000Z/PT5H30M"]
	reservations = ReservationPlan.upcoming({ start: "19970101T180000Z", rule: "FREQ=DAILY;COUNT=2", query_start: "19970101T000000Z", query_end: "19970105T000000Z", duration: "PT1H", periods })?
	echo!("Equipment reservations (UTC)\n")
	for reservation in reservations {
		echo!(ReservationPlan.report(reservation)?)
	}
	Ok({})
}
