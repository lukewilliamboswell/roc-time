import time.Explanation
import time.Ixdtf
import time.OffsetTimestamp
import time.PosixSpan
import time.ZoneRules
import time.FixedOffset

## Explain a declaration, then explain its bound result without resolving again.
AnnotationExplanation :: [].{
	review = |text| {
		declaration = match Ixdtf.parse(text) {
			Ok(value) => value
			Err(error) => return Err(Input(error))
		}
		# Explicit narrow fixture for RFC 9557 section 3.3, not a Paris database.
		start : OffsetTimestamp
		start = "2022-07-08T00:00:00Z"
		end : OffsetTimestamp
		end = "2022-07-08T01:00:00Z"
		validity = PosixSpan.new(OffsetTimestamp.boundary(start)?, OffsetTimestamp.boundary(end)?)?
		rules = ZoneRules.new_bounded("Europe/Paris", "rfc9557-example", validity, FixedOffset.from_seconds(7200), [], { minimum: 7200, maximum: 7200 })?
		snapshot = match Ixdtf.resolve(declaration, Some(rules)) {
			Ok(value) => value
			Err(error) => return Err(Interpretation(error))
		}
		limits = { max_facts: 16, max_utf8_bytes: 4096 }
		Ok({
			source: Explanation.plain(Explanation.new(Ixdtf(declaration)), limits),
			snapshot: Explanation.plain(Explanation.new(Snapshot(snapshot)), limits),
		})
	}
}
