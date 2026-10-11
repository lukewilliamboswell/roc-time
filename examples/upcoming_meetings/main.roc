app [main!] {
	roc: "nightly-2026-09-27-a3ce7f1",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-GPETAiR4TeEPxDA1F6qHxbDnFexmj4tYgUrkEryBhtdP.tar.zst",
	zones: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-tzdb-Ew1nW7PzcwxnidgmDydRHnYyQRB4sjq2dD7H2DDpsyMj.tar.zst",
}
import MeetingSchedule
import zones.Database
import time.ZoneRules

main! = |_args| {
	rules = ZoneRules.from_database(Database.get("Europe/Paris")?)?
	meeting = MeetingSchedule.prepare(rules, { start: "20260322T090000", rule: "FREQ=WEEKLY;COUNT=4", duration: "PT1H", mode: Zoned, inclusions: [], exclusions: ["20260405T070000Z"], periods: [] })?
	window = { start: MeetingSchedule.local("2026-03-20T00:00")?, end: MeetingSchedule.local("2026-04-15T00:00")? }
	limits = { work: { max_steps: 1000, max_buffered: 32, max_zone_segments: 100000, max_zone_candidates: 8 }, max_occurrences: 1 }
	var $batch = MeetingSchedule.query(meeting, "team-meeting", window, limits)?
	echo!("Upcoming Paris meetings; one result per page\n")
	while Bool.True {
		for item in $batch.occurrences {
			echo!("${MeetingSchedule.describe(item)?} Paris\n")
		}
		match $batch.status {
			Complete => break
			Limited(progress) => {
				match progress.reason {
					OutputLimit => {
						echo!("Next page\n")
						$batch = MeetingSchedule.resume(progress.cursor, limits)?
					}
					_ => return Err(WorkBudgetReached(progress.reason))
				}
			}
		}
	}
	echo!("Complete; cancelled starts do not replenish COUNT.\n")
	Ok({})
}
