app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0/roc-time-6gt2mALoAXMVKcQvCpdisfaAU3S9XVdV3vR2CNA7e43t.tar.zst",
	zones: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0/roc-time-tzdb-3JTmpDV26cHNH7cN1HqHzUWTZKpyaYgLYkWSws8Tqj3e.tar.zst",
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
