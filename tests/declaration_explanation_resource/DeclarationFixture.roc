import time.Explanation
import time.ExactInterval
import time.ICalDateTime
import time.ICalDuration
import time.ICalPeriod
import time.SemanticFact
import time.PosixSpan
import time.PosixBoundary
import time.ClockTime
import time.LocalDateTime

DeclarationFixture := [].{
	source : U8, I64, Bool -> Explanation.Source
	source = |kind, days, local| {
		suffix = if local {
			""
		} else {
			"Z"
		}
		date = "19700101T000000${suffix}"
		duration = "P${days.to_str()}DT1S"
		match kind {
			0 => ExactInterval(
				match ExactInterval.parse("1970-01-01T00:00:00.000001${
					if local {
						"+00:00"
					} else {
						"Z"
					}
				}/1970-01-01T00:00:00.000002Z") {
					Ok(v) => v
					Err(_) => crash "fixture exact"
				},
			)
			1 => ICalDateTime(
				match ICalDateTime.parse(date) {
					Ok(v) => v
					Err(_) => crash "fixture datetime"
				},
			)
			2 => ICalDuration(
				match ICalDuration.parse(duration) {
					Ok(v) => v
					Err(_) => crash "fixture duration"
				},
			)
			_ => ICalPeriod(
				match ICalPeriod.parse(
					"${date}/${
						if kind == 3 {
							"19700101T000001${suffix}"
						} else {
							duration
						}
					}",
				) {
					Ok(v) => v
					Err(_) => crash "fixture period"
				},
			)
		}
	}
	inspect : Explanation.Source -> Str
	inspect = |declaration| match declaration {
		ExactInterval(v) => Str.inspect(v)
		ICalDateTime(v) => Str.inspect(v)
		ICalDuration(v) => Str.inspect(v)
		ICalPeriod(v) => Str.inspect(v)
		_ => crash "fixture source domain"
	}
	matches : SemanticFact, U8, I64, Bool -> Bool
	matches = |fact, kind, days, local| match SemanticFact.kind(fact) {
		ExactIntervalDescription(data) => kind == 0 and PosixSpan.start(data.span) == PosixBoundary.from_microseconds(1) and PosixSpan.end(data.span) == PosixBoundary.from_microseconds(2)
		ICalDateTimeDescription(data) => kind == 1 and data.role == Standalone and data.form == (
			if local {
				Local
			} else {
				Utc
			}
		) and ClockTime.to_microseconds_since_midnight(LocalDateTime.clock(data.local)) == 0
		ICalDurationDescription(data) => kind == 2 and data.role == Standalone and data.days == days and data.seconds == 1
		ICalPeriodDescription(data) => (kind == 3 or kind == 4) and data.form == (
			if local {
				Local
			} else {
				Utc
			}
		) and match data.ending {
			Endpoint(end) => kind == 3 and ClockTime.to_microseconds_since_midnight(LocalDateTime.clock(end)) == 1000000
			Duration(amount) => kind == 4 and amount.days == days and amount.seconds == 1
		}
		_ => False
	}
}
