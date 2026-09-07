import time.Explanation
import time.ICalDuration
import time.ICalPeriod
import time.ExactInterval

## Review imported scheduling terms before selecting interpretation context.
EventTerms :: [].{
	review = |durations, periods, exact_text| {
		limits = { max_facts: 8, max_utf8_bytes: 4096 }
		var $reports = []
		for text in durations {
			value = match ICalDuration.parse(text) {
				Ok(found) => found
				Err(error) => return Err(Duration(error))
			}
			$reports = $reports.append({ label: text, report: Explanation.plain(Explanation.new(ICalDuration(value)), limits) })
		}
		for text in periods {
			value = match ICalPeriod.parse(text) {
				Ok(found) => found
				Err(error) => return Err(Period(error))
			}
			$reports = $reports.append({ label: text, report: Explanation.plain(Explanation.new(ICalPeriod(value)), limits) })
		}
		exact = match ExactInterval.parse(exact_text) {
			Ok(found) => found
			Err(error) => return Err(Exact(error))
		}
		# Both offsets are explicit input assertions. No zone database is inferred.
		Ok($reports.append({ label: exact_text, report: Explanation.plain(Explanation.new(ExactInterval(exact)), limits) }))
	}
}
