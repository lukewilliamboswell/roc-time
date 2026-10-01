import time.ICalDateRule
import time.ICalTimedRule
import time.Explanation

## Review imported declarations before selecting a query window or zone rules.
SeriesReview :: [].{
	review = |date_parts, timed_parts| {
		dates = match ICalDateRule.parse(date_parts) {
			Ok(value) => value
			Err(error) => return Err(DateRule(error))
		}
		timed = match ICalTimedRule.parse(timed_parts) {
			Ok(value) => value
			Err(error) => return Err(TimedRule(error))
		}
		limits = { max_facts: 40, max_utf8_bytes: 8192 }
		Ok([
			{ title: "One counted date, excluded; an additional date remains", report: Explanation.plain(Explanation.new(DateRecurrence(dates)), limits) },
			{ title: "Weekly meeting with no termination; zone rules still required", report: Explanation.plain(Explanation.new(ICalTimedRule(timed)), limits) },
		])
	}
}
