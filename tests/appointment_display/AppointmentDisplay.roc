import time.CalendarDate
import time.EnglishGregorian
import time.LocalDateTime

## Present local appointment labels with explicitly chosen display precision.
## These labels have no selected zone or resolved timeline occurrence.
AppointmentDisplay :: [].{
	describe = |appointment_text, recorded_text| {
		appointment = parse(appointment_text)?
		recorded = parse(recorded_text)?
		day = CalendarDate.as_gregorian(LocalDateTime.date(appointment))?
		heading = match EnglishGregorian.local_datetime(appointment, Minute) {
			Ok(value) => value
			Err(error) => return Err(Display(error))
		}
		clock = match EnglishGregorian.clock(LocalDateTime.clock(appointment), Second) {
			Ok(value) => value
			Err(error) => return Err(ClockDisplay(error))
		}
		exact = match EnglishGregorian.local_datetime(recorded, Exact) {
			Ok(value) => value
			Err(error) => return Err(Display(error))
		}
		lines = [
			"Appointment: ${heading}",
			"Date: ${EnglishGregorian.date(day)}",
			"Scheduled clock: ${clock}",
			"Recorded local label: ${exact}",
		]
		Ok(lines)
	}
}

parse = |text| match LocalDateTime.parse_gregorian(text) {
	Ok(value) => Ok(value)
	Err(error) => Err(Input(error))
}
