app [main!] {
	time: "../../package/main.roc",
	zones: "../../tzdb/package/main.roc",
}
import DispatchDeadlines
import zones.Database
import time.ZoneRules
main! = |_args| {
	data = Database.get("Australia/Melbourne")?
	rules = ZoneRules.from_database(data)?
	start = DispatchDeadlines.midnight(2025, 3, 1)?
	end = DispatchDeadlines.midnight(2025, 5, 1)?
	deadlines = DispatchDeadlines.upcoming(rules, { start, end })?
	echo!("Remaining deadlines for the four-month dispatch contract\nFinal Monday, final pickup slot; March and April 2025\nJanuary waived; the original contract still ends in April.\n")
	for deadline in deadlines {
		match DispatchDeadlines.report(deadline) {
			Ok(text) => echo!(text)
			Err(_) => return Err(DisplayOutOfRange)
		}
	}
	Ok({})
}
