app [main!] {
	time: "../../package/main.roc",
	zones: "../../tzdb/package/main.roc",
}
import LoanSchedule
import zones.Database
import time.ZoneRules
main! = |_args| {
	data = Database.get("Australia/Melbourne")?
	rules = ZoneRules.from_database(data)?
	loans = LoanSchedule.upcoming(rules)?
	echo!("Equipment loans starting on the 31st\nOne calendar month; return dates clamp to month end. Melbourne local times.\n")
	for loan in loans {
		match LoanSchedule.report(loan) {
			Ok(text) => echo!(text)
			Err(_) => return Err(InvalidReport)
		}
	}
	Ok({})
}
