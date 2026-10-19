app [main!] { pf: platform "../../platform/main.roc", time: "../../../package/main.roc" }
import pf.Host
import time.TimedRecurrence
import time.TimedSchedule
import time.TimedOccurrence
import time.CalendarPattern
import time.Calendar
import time.GregorianDate
import time.ClockTime
import time.LocalDateTime
import time.PosixBoundary
import time.PosixSpan
import time.PosixDelta
import time.FixedOffset
import time.ZoneRules

# Input storage/rule validation is outside cursor measurements. Keep a second
# cursor reference alive so first consumption exercises shared state. Counter
# scope is cumulative requested allocation bytes, not live/retained memory.
main! = |args| {
	year = I64.from_str(args.get(1) ?? "200000") ?? crash "year argument"
	ceiling = U64.from_str(args.get(2) ?? "65536") ?? crash "ceiling argument"
	stage = args.get(3) ?? "all"
	limit = |name| if stage == "all" or stage == name {
		ceiling
	} else {
		4096.U64
	}
	Host.assert!(year >= 1971 and year <= 200000)
	anchor_date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 }) ?? crash "anchor"
	clock = ClockTime.from_fields({ hour: 1, minute: 30, second: 0, microsecond: 0 }) ?? crash "clock"
	anchor = LocalDateTime.new(Calendar.Date.from_gregorian(anchor_date), clock)
	end_date = GregorianDate.from_fields({ year, month: 1, day: 1 }) ?? crash "horizon"
	end = LocalDateTime.new(Calendar.Date.from_gregorian(end_date), clock)
	validity = PosixSpan.new(PosixBoundary.from_microseconds(I64.lowest), PosixBoundary.from_microseconds(I64.highest)) ?? crash "validity"
	rules = ZoneRules.new_bounded("Synthetic/Composed", "integer-minute-v1", validity, FixedOffset.from_seconds(0), [{ at: PosixBoundary.from_microseconds(7200000000), offset: FixedOffset.from_seconds(3600) }], { minimum: 0, maximum: 3600 }) ?? crash "rules"
	rule = TimedRecurrence.new({ date: anchor_date, clock }, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [1, 2, 3, 4], minutes: [30], seconds: [] }, termination: Forever, by_set_pos: [] }) ?? crash "rule"
	end_clock = ClockTime.from_fields({ hour: 5, minute: 30, second: 0, microsecond: 0 }) ?? crash "end clock"
	ending = AtLocal({ source: LocalDateTime.new(Calendar.Date.from_gregorian(anchor_date), end_clock), occurrence: First, gap: UseOffsetBeforeGap })
	overrides = [{ source: anchor, ending }]
	default = Coordinate(PosixDelta.from_microseconds(3600000000))
	before = Host.allocated_bytes!({})
	cursor = TimedSchedule.new_with_endings("prefix", rule, { start: anchor, end }, default, overrides, { rules, occurrence: First, gap: UseOffsetBeforeGap }) ?? crash "cursor"
	constructed = Host.allocated_bytes!({})
	Host.assert!(constructed - before <= limit("construction"))
	var $current = cursor
	var $calls = 0.U64
	var $seen = 0.U64
	var $first_bytes = 0.U64
	var $first_work = 0.U64
	var $work = 0.U64
	while $calls < 100 and $seen < 2 {
		batch = TimedSchedule.collect($current, { work: { max_steps: 1, max_buffered: 4, max_zone_segments: 1, max_zone_candidates: 2 }, max_occurrences: 1 }) ?? crash "bounded prefix"
		Host.assert!(batch.steps <= 1 and batch.zone_segments <= 1 and batch.occurrences.len() <= 1)
		$work = $work + batch.steps + batch.zone_segments
		for occurrence in batch.occurrences {
			span = TimedOccurrence.span(occurrence)
			if $seen == 0 {
				Host.assert!(TimedOccurrence.id(occurrence) == { series: "prefix", source: anchor })
				Host.assert!(PosixBoundary.to_microseconds(PosixSpan.start(span)) == 5400000000 and PosixBoundary.to_microseconds(PosixSpan.end(span)) == 16200000000)
				$first_bytes = Host.allocated_bytes!({})
				$first_work = $work
			} else {
				Host.assert!(PosixBoundary.to_microseconds(PosixSpan.start(span)) == 9000000000 and PosixBoundary.to_microseconds(PosixSpan.end(span)) == 12600000000)
			}
			$seen = $seen + 1
		}
		match batch.status {
			Complete => crash "huge schedule falsely complete"
			Limited(progress) => {
				$current = progress.cursor
			}
		}
		$calls = $calls + 1
	}
	consumed = Host.allocated_bytes!({})
	Host.assert!($seen == 2)
	Host.assert!($first_bytes - constructed <= limit("first"))
	Host.assert!(consumed - $first_bytes <= limit("resume"))
	# Reusing the saved snapshot starts at the original source, independently
	# of the resumed cursor. These checks run after the recorded scopes.
	Host.assert!(TimedSchedule.to_inspect(cursor).count_utf8_bytes() <= 256)
	var $saved = cursor
	var $saved_calls = 0.U64
	var $replayed = Bool.False
	while $saved_calls < 100 and !$replayed {
		batch = TimedSchedule.collect($saved, { work: { max_steps: 1, max_buffered: 4, max_zone_segments: 1, max_zone_candidates: 2 }, max_occurrences: 1 }) ?? crash "saved cursor prefix"
		Host.assert!(batch.steps <= 1 and batch.zone_segments <= 1)
		for occurrence in batch.occurrences {
			Host.assert!(TimedOccurrence.id(occurrence) == { series: "prefix", source: anchor })
			span = TimedOccurrence.span(occurrence)
			Host.assert!(PosixBoundary.to_microseconds(PosixSpan.start(span)) == 5400000000 and PosixBoundary.to_microseconds(PosixSpan.end(span)) == 16200000000)
			$replayed = Bool.True
		}
		match batch.status {
			Complete => crash "saved huge cursor falsely complete"
			Limited(progress) => {
				$saved = progress.cursor
			}
		}
		$saved_calls = $saved_calls + 1
	}
	Host.assert!($replayed)
	output = "${(constructed - before).to_str()},${($first_bytes - constructed).to_str()},${(consumed - $first_bytes).to_str()},${$first_work.to_str()},${($work - $first_work).to_str()}\n"
	{ bytes: output.to_utf8(), work: [constructed - before, $first_bytes - constructed, consumed - $first_bytes] }
}
