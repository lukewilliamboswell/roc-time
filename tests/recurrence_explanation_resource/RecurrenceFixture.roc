import time.DateRecurrence
import time.TimedRecurrence
import time.RfcTimedRule
import time.CalendarPattern
import time.GregorianDate
import time.ClockTime
import time.CivilDay

RecurrenceFixture := [].{
	make = |count, finite| {
		var $dates = []
		var $starts = []
		var $texts = []
		clock = match ClockTime.from_microseconds_since_midnight(count.to_i64() - count.to_i64()) {
			Ok(v) => v
			Err(_) => crash "fixture clock"
		}
		var $i = 0.U32
		while $i < count {
			date = match GregorianDate.from_civil_day(CivilDay.from_day_number($i.to_i64())) {
				Ok(v) => v
				Err(_) => crash "fixture date"
			}
			$dates = $dates.append(date)
			$starts = $starts.append({ date, clock })
			fields = GregorianDate.to_fields(date)
			$texts = $texts.append("${fields.year.to_str()}${pad(fields.month)}${pad(fields.day)}T000000")
			$i = $i + 1
		}
		anchor = match $dates.get(0) {
			Ok(v) => v
			Err(_) => crash "nonempty fixture"
		}
		selectors = List.repeat(1.I16, count.to_u64())
		months = List.repeat(1.U8, count.to_u64())
		pattern = { ..CalendarPattern.defaults(Daily), by_month: months }
		date_rule = match DateRecurrence.new(
			anchor,
			{
				pattern,
				termination: if finite {
					Count(U64.highest)
				} else {
					Forever
				},
				by_set_pos: selectors,
				inclusions: $dates,
				exclusions: [],
			},
		) {
			Ok(v) => v
			Err(_) => crash "native date rule"
		}
		timed_base = match TimedRecurrence.new(
			{ date: anchor, clock },
			{
				calendar: pattern,
				clocks: { hours: [], minutes: [], seconds: [] },
				termination: if finite {
					Count(U64.highest)
				} else {
					Forever
				},
				by_set_pos: selectors,
			},
		) {
			Ok(v) => v
			Err(_) => crash "native timed rule"
		}
		timed_rule = match TimedRecurrence.with_inclusions(timed_base, $starts) {
			Ok(v) => v
			Err(_) => crash "timed inclusions"
		}
		rfc_rule = match RfcTimedRule.parse({
			start: "19700101T000000",
			rule: if finite {
				"FREQ=DAILY;COUNT=2147483647"
			} else {
				"FREQ=DAILY"
			},
			duration: "PT1S",
			inclusions: $texts,
			exclusions: [],
			periods: [],
			mode: Floating,
		}) {
			Ok(v) => v
			Err(_) => crash "rfc rule"
		}
		{ date_rule, timed_rule, rfc_rule, dates: $dates, starts: $starts, texts: $texts, selectors, months }
	}
}

pad = |value| if value < 10 {
	"0${value.to_str()}"
} else {
	value.to_str()
}
