app [main!] {
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc1/roc-time-2T6KR7B59FhCSNghyPAgP2j61YiU1F537CkB6UFUwzfY.tar.zst",
	zones: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc1/roc-time-tzdb-5xpCNbPVbrBRi2GC7kKEg91eQVjLQrkAb5F1FHy4THgD.tar.zst",
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
