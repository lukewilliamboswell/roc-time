app [main!] {
	time: "../../package/main.roc",
	zones: "../../tzdb/package/main.roc",
}
import MeetingSchedule
import zones.Database
import time.ZoneRules

main! = |_args| {
	rules = ZoneRules.from_database(Database.get("Europe/Paris")?)?
	meeting = MeetingSchedule.prepare(rules, { start: "20260322T090000", rule: "FREQ=WEEKLY;COUNT=4", duration: "PT1H", mode: Zoned, exclusions: ["20260405T070000Z"] })?
	window = { start: MeetingSchedule.local("2026-03-20T00:00")?, end: MeetingSchedule.local("2026-04-15T00:00")? }
	query = meeting.open_query({ series: "team-meeting", window })?
	var $batch = query.page(1)?
	echo!("Upcoming Paris meetings; one result per page\n")
	while Bool.True {
		for! item in $batch.occurrences.iter().stream() {
			echo!("${MeetingSchedule.describe(item)?} Paris\n")
		}
		match $batch.status {
			Complete => break
			Limited(progress) => {
				match progress.reason {
					OutputLimit => {
						echo!("Next page\n")
						$batch = progress.query.page(1)?
					}
					_ => return Err(WorkBudgetReached(progress.reason))
				}
			}
		}
	}
	echo!("Complete; cancelled starts do not replenish COUNT.\n")
	Ok({})
}
