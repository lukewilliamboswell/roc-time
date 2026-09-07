app [main!] {
	roc: "nightly-2026-09-06-d85e877",
	time: "../../package/main.roc",
	zones: "../../tzdb/package/main.roc",
}
import ZonedAppointment
import time.OffsetTimestamp
import time.PosixSpan
import time.ZoneRules

main! = |_args| {
	paris = ZonedAppointment.rules("Europe/Paris")?
	new_york = ZonedAppointment.rules("America/New_York")?
	echo!("Paris appointments, displayed in New York\n")
	for source in ["2026-03-28T09:30", "2026-10-24T09:30"] {
		pair = ZonedAppointment.compare_days(paris, new_york, source, RequireUnique)?
		hours = I64.div_trunc_by(pair.coordinate_microseconds, 3600000000)
		echo!("${source}: ${pair.first_display} -> ${pair.next_display}; ${hours.to_str()} POSIX coordinate hours\n")
	}
	fold = ZonedAppointment.parse("2026-10-25T02:30")?
	echo!("Repeated Paris label: 25 Oct 2026, 02:30\n")
	match ZonedAppointment.classify(paris, fold)? {
		Fold(boundaries) => for boundary in boundaries {
			offset = ZoneRules.offset_at(paris, boundary)?
			stamp = match OffsetTimestamp.from_boundary(boundary, Asserted(offset), 0) {
				Ok(value) => value
				Err(error) => return Err(Timestamp(error))
			}
			view = ZonedAppointment.project(new_york, boundary)?
			echo!("Choice: ${OffsetTimestamp.to_text(stamp)}; ${view.text} in New York\n")
		}
		Unique(_) => echo!("This label has one occurrence.\n")
		Gap => echo!("This label has no occurrence.\n")
	}
	selected = ZonedAppointment.resolve(paris, fold, Last)?
	view = ZonedAppointment.project(new_york, selected)?
	echo!("Explicitly choosing Last: ${view.text} in New York\n")
	gap = ZonedAppointment.parse("2026-03-29T02:30")?
	match ZonedAppointment.resolve(paris, gap, RequireUnique) {
		Ok(_) => echo!("Spring label resolved.\n")
		Err(error) => echo!("Spring label needs attention: ${Str.inspect(error)}\n")
	}
	report_unknown_zone!("Example/Unknown")
	match ZonedAppointment.project(paris, PosixSpan.end(ZoneRules.validity(paris))) {
		Ok(_) => echo!("Requested date is within the supplied rules.\n")
		Err(error) => echo!("Beyond supplied rules: ${Str.inspect(error)}\n")
	}
	Ok({})
}

report_unknown_zone! = |name| match ZonedAppointment.rules(name) {
	Ok(_) => echo!("Requested zone found.\n")
	Err(error) => echo!("Zone lookup needs attention: ${Str.inspect(error)}\n")
}
