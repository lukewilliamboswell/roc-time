import time.CalendarDate
import time.ClockTime
import time.LocalDateTime
import time.ZoneRules
import time.PosixSpan
import time.PosixDelta

## An overnight team works 22:00 to 06:00 under explicit local zone rules.
Staffing :: { zone : Str, hours : I64 }.{
	overnight = |rules, evening, morning| {
		start_date = CalendarDate.from_fields(Gregorian, evening)?
		end_date = CalendarDate.from_fields(Gregorian, morning)?
		start_clock = ClockTime.from_fields({ hour: 22, minute: 0, second: 0, microsecond: 0 })?
		end_clock = ClockTime.from_fields({ hour: 6, minute: 0, second: 0, microsecond: 0 })?
		shift = ZoneRules.appointment(rules, LocalDateTime.new(start_date, start_clock), RequireUnique, LocalDateTime.new(end_date, end_clock), RequireUnique)?
		width = PosixSpan.coordinate_width(shift)?
		micros = PosixDelta.to_microseconds(width)
		if I64.rem_by(micros, 3600000000) != 0 {
			return Err(FractionalShiftHours)
		}
		Ok({ zone: ZoneRules.name(rules), hours: I64.div_trunc_by(micros, 3600000000) })
	}
	report = |shift| "Overnight staffing in ${shift.zone}\nLocal shift: 22:00 to 06:00 across the spring clock change\nBudget ${shift.hours.to_str()} hours per team member.\n"
}
