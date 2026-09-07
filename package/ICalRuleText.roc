import CalendarPattern
import ClockPattern
import SubdailyPattern
import ICalRuleParts

# Canonical extracted RRULE rendering; no interpretation or occurrence expansion.
ICalRuleText :: [].{
	render : ICalRuleParts.Fields -> Try(Str, ICalRuleParts.Error)
	render = |fields| {
		{ pattern, clocks, subdaily, termination, positions } = fields
		ICalRuleParts.validate_profile(pattern, positions, clocks)?
		frequency = match subdaily {
			Some(Hourly) => "HOURLY"
			Some(Minutely) => "MINUTELY"
			Some(Secondly) => "SECONDLY"
			None => match pattern.frequency {
				Daily => "DAILY"
				Weekly => "WEEKLY"
				Monthly => "MONTHLY"
				Yearly => "YEARLY"
			}
		}
		var $fields = ["FREQ=${frequency}", "INTERVAL=${pattern.interval.to_str()}"]
		match termination {
			Forever => {}
			Count(count) => {
				if count > 2147483647 {
					return Err(OutOfRange("COUNT"))
				}
				$fields = $fields.append("COUNT=${count.to_str()}")
			}
			Until(date) => {
				$fields = $fields.append("UNTIL=${date}")
			}
		}
		for (name, values) in [
			("BYMONTH", pattern.by_month.map(|n| n.to_i64())),
			("BYWEEKNO", pattern.by_week_no.map(|n| n.to_i64())),
			("BYYEARDAY", pattern.by_year_day.map(|n| n.to_i64())),
			("BYMONTHDAY", pattern.by_month_day.map(|n| n.to_i64())),
		] {
			if !values.is_empty() {
				$fields = $fields.append("${name}=${number_set(values)}")
			}
		}
		if !pattern.by_day.is_empty() {
			keys = pattern.by_day.map(|day| weekday_number(day.weekday) * 128 + day.ordinal.to_i64() + 53)
			days = unique_numbers(keys).map(
				|key| {
					ordinal = I64.mod_by(key, 128) - 53
					prefix = if ordinal == 0 {
						""
					} else {
						ordinal.to_str()
					}
					"${prefix}${weekday_at(I64.div_trunc_by(key, 128))}"
				},
			)
			$fields = $fields.append("BYDAY=${Str.join_with(days, ",")}")
		}
		for (name, values) in [("BYHOUR", clocks.hours.map(|n| n.to_i64())), ("BYMINUTE", clocks.minutes.map(|n| n.to_i64())), ("BYSECOND", clocks.seconds.map(|n| n.to_i64()))] {
			if !values.is_empty() {
				$fields = $fields.append("${name}=${number_set(values)}")
			}
		}
		if !positions.is_empty() {
			$fields = $fields.append("BYSETPOS=${number_set(positions.map(|n| n.to_i64()))}")
		}
		$fields = $fields.append("WKST=${weekday_at(weekday_number(pattern.week_start))}")
		Ok(Str.join_with($fields, ";"))
	}
}

unique_numbers : List(I64) -> List(I64)
unique_numbers = |values| {
	ordered = values.sort_with(
		|a, b| if a < b {
			Before
		} else if a > b {
			After
		} else {
			Same
		},
	)
	var $result = []
	var $previous = None
	for value in ordered {
		if $previous != Some(value) {
			$result = $result.append(value)
		}
		$previous = Some(value)
	}
	$result
}

number_set = |values| Str.join_with(unique_numbers(values).map(|n| n.to_str()), ",")

weekday_number : CalendarPattern.Weekday -> I64
weekday_number = |day| match day {
	Monday => 0
	Tuesday => 1
	Wednesday => 2
	Thursday => 3
	Friday => 4
	Saturday => 5
	Sunday => 6
}

# Only called with the quotient of a validated weekday/ordinal encoding.
weekday_at = |index| match index {
	0 => "MO"
	1 => "TU"
	2 => "WE"
	3 => "TH"
	4 => "FR"
	5 => "SA"
	6 => "SU"
	_ => crash "Validated weekday index"
}
