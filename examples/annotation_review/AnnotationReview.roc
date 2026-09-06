import time.Ixdtf
import time.OffsetTimestamp
import time.ZoneRules
import time.FixedOffset
import time.PosixSpan
import time.LocalDateTime
import time.ClockTime

## Review a saved timestamp's zone assertion and calendar presentation request.
AnnotationReview :: [].{
	review = |texts| {
		# A deliberately narrow fixture for RFC 9557 section 3.3's Paris example,
		# not a general Paris provider. Applications supply their own loaded rules.
		start = timestamp("2022-07-08T00:00:00Z")?
		end = timestamp("2022-07-08T01:00:00Z")?
		validity = PosixSpan.new(OffsetTimestamp.boundary(start)?, OffsetTimestamp.boundary(end)?)?
		rules = ZoneRules.new_bounded("Europe/Paris", "rfc9557-example", validity, FixedOffset.from_seconds(7200), [], { minimum: 7200, maximum: 7200 })?
		var lines = []
		for text in texts {
			value = match Ixdtf.parse(text) {
				Ok(found) => found
				Err(error) => return Err(Input(error))
			}
			canonical = Ixdtf.to_text(value)
			result = match Ixdtf.resolve(value, Some(rules)) {
				Err(OffsetConflict) => "offset assertion conflicts with supplied Paris rules"
				Err(error) => return Err(Interpretation(error))
				Ok(snapshot) => match Ixdtf.Snapshot.presentation(snapshot) {
					Ok(local) => {
						clock = ClockTime.to_fields(LocalDateTime.clock(local))
						"Paris clock ${pad(clock.hour)}:${pad(clock.minute)}:${pad(clock.second)}"
					}
					Err(UnsupportedCalendar(_)) => "calendar preference preserved; presentation unsupported"
				}
			}
			lines = lines.append("${canonical} -> ${result}")
		}
		Ok(lines)
	}
}

timestamp = |text| match OffsetTimestamp.parse(text) {
	Ok(value) => Ok(value)
	Err(error) => Err(Timestamp(error))
}

pad = |number| if number < 10 {
	"0${number.to_str()}"
} else {
	number.to_str()
}
