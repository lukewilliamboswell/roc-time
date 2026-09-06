import time.Explanation
import time.ExactInterval
import time.RfcDateTime
import time.RfcDuration
import time.RfcPeriod
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
			1 => RfcDateTime(
				match RfcDateTime.parse(date) {
					Ok(v) => v
					Err(_) => crash "fixture datetime"
				},
			)
			2 => RfcDuration(
				match RfcDuration.parse(duration) {
					Ok(v) => v
					Err(_) => crash "fixture duration"
				},
			)
			_ => RfcPeriod(
				match RfcPeriod.parse(
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
		RfcDateTime(v) => Str.inspect(v)
		RfcDuration(v) => Str.inspect(v)
		RfcPeriod(v) => Str.inspect(v)
		_ => crash "fixture source domain"
	}
	matches : SemanticFact, U8, I64, Bool -> Bool
	matches = |fact, kind, days, local| match SemanticFact.kind(fact) {
		ExactIntervalDescription(data) => kind == 0 and PosixSpan.start(data.span) == PosixBoundary.from_microseconds(1) and PosixSpan.end(data.span) == PosixBoundary.from_microseconds(2)
		RfcDateTimeDescription(data) => kind == 1 and data.role == Standalone and data.form == (
			if local {
				Local
			} else {
				Utc
			}
		) and ClockTime.to_microseconds_since_midnight(LocalDateTime.clock(data.local)) == 0
		RfcDurationDescription(data) => kind == 2 and data.role == Standalone and data.days == days and data.seconds == 1
		RfcPeriodDescription(data) => (kind == 3 or kind == 4) and data.form == (
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
