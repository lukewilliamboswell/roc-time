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
	echo!("Equipment loans: monthly starts and one extra booking\nMonthly loans clamp to month end; the extra booking lasts one week. Melbourne local times.\n")
	for loan in loans {
		match LoanSchedule.report(loan) {
			Ok(text) => echo!(text)
			Err(_) => return Err(InvalidReport)
		}
	}
	Ok({})
}
