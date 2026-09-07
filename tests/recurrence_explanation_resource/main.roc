app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.Explanation
import time.SemanticFact
import time.DateRecurrence
import time.TimedRecurrence
import time.RfcTimedRule
import time.GregorianDate
import time.CalendarDate
import time.LocalDateTime
import time.CivilDay
import time.ClockTime
import RecurrenceFixture

# R02/R11/R12/R15/R16: construction validates and normalizes shared source lists before
# measurement. Forever and maximum COUNT are logical declarations, not work to
# enumerate. Counters measure allocation traffic, not retained/live memory.
main! = |args| {
	count = U32.from_str(args.get(1) ?? "4096") ?? 4096
	finite = (args.get(2) ?? "forever") == "count"
	kind = args.get(3) ?? "date"
	ceiling = U64.from_str(args.get(4) ?? "65536") ?? 65536
	Host.assert!(count == 2 or count == 4096)
	input = RecurrenceFixture.make(count, finite)
	source = match kind {
		"date" => DateRecurrence(input.date_rule)
		"timed" => TimedRecurrence(input.timed_rule)
		_ => RfcTimedRule(input.rfc_rule)
	}
	before = Host.allocated_bytes!({})
	explanation = Explanation.new(source)
	constructed = Host.allocated_bytes!({})
	total = Explanation.fact_count(explanation)
	Host.assert!(total > count.to_u64())
	var $i = 0.U32
	while $i < 100000 {
		match Explanation.fact_at(explanation, 0) {
			Item(fact) => Host.assert!(
				match SemanticFact.kind(fact) {
					RecurrenceDescription(data) => kind != "rfc" and data.frequency == Daily and data.interval == 1 and data.inclusion_count == count.to_u64() and data.exclusion_count == 0 and data.selector_count == count.to_u64() * 2 + (
						if kind == "date" {
							0
						} else {
							4
						}
					)
					RfcTimedRuleDescription(data) => kind == "rfc" and data.mode == Floating and data.period_count == 0
					_ => False
				},
			)
			End => Host.assert!(False)
		}
		match Explanation.fact_at(explanation, total - 1) {
			Item(fact) => Host.assert!(
				match SemanticFact.kind(fact) {
					RecurrenceException(data) => data.kind == Inclusion and (match data.source {
						Date(date) => CivilDay.to_day_number(GregorianDate.to_civil_day(date)) == count.to_i64() - 1
						Local(local) => CivilDay.to_day_number(CalendarDate.to_civil_day(LocalDateTime.date(local))) == count.to_i64() - 1
					})
					_ => False
				},
			)
			End => Host.assert!(False)
		}
		$i = $i + 1
	}
	match Explanation.fact_at(
		explanation,
		if kind == "rfc" {
			4
		} else {
			1
		},
	) {
		Item(fact) => Host.assert!(
			match SemanticFact.kind(fact) {
				RecurrenceTermination(Forever) => !finite
				RecurrenceTermination(Count(value)) => finite and value == (
					if kind == "rfc" {
						2147483647
					} else {
						U64.highest
					}
				)
				_ => False
			},
		)
		End => Host.assert!(False)
	}
	read = Host.allocated_bytes!({})
	zero = Explanation.plain(explanation, { max_facts: 0, max_utf8_bytes: 4096 })
	empty = Explanation.plain(explanation, { max_facts: 3, max_utf8_bytes: 0 })
	zero_after = Host.allocated_bytes!({})
	Host.assert!(constructed == before and read == constructed and zero_after == read)
	Host.assert!(zero.visited_facts == 0 and empty.visited_facts == 0 and zero.text == "" and empty.text == "" and zero.status == Limited(FactLimit) and empty.status == Limited(ByteLimit))
	tiny = Explanation.plain(explanation, { max_facts: 1, max_utf8_bytes: 4 })
	tiny_after = Host.allocated_bytes!({})
	Host.assert!(tiny.visited_facts == 1 and tiny.text.count_utf8_bytes() <= 4 and tiny.status == Limited(ByteLimit) and tiny_after - zero_after <= ceiling)
	fixed = Explanation.plain(explanation, { max_facts: 3, max_utf8_bytes: 4096 })
	fixed_after = Host.allocated_bytes!({})
	Host.assert!(fixed.visited_facts == 3 and fixed.status == Limited(FactLimit) and fixed.text.count_utf8_bytes() <= 4096 and fixed_after - tiny_after <= ceiling)
	summary = match source {
		DateRecurrence(v) => Str.inspect(v)
		TimedRecurrence(v) => Str.inspect(v)
		RfcTimedRule(v) => Str.inspect(v)
		_ => crash "source"
	}
	inspected = Host.allocated_bytes!({})
	Host.assert!(summary.count_utf8_bytes() <= 256 and inspected - fixed_after <= ceiling)
	# Original shared lists remain observable after explanation consumption.
	Host.assert!(input.dates.len() == count.to_u64() and input.starts.len() == count.to_u64() and input.texts.len() == count.to_u64() and input.selectors.len() == count.to_u64() and input.months.len() == count.to_u64())
	match input.dates.get(0) {
		Ok(date) => Host.assert!(GregorianDate.to_fields(date) == { year: 1970, month: 1, day: 1 })
		Err(_) => Host.assert!(False)
	}
	match input.starts.get(count.to_u64() - 1) {
		Ok(start) => Host.assert!(CivilDay.to_day_number(GregorianDate.to_civil_day(start.date)) == count.to_i64() - 1 and ClockTime.to_fields(start.clock).hour == 0)
		Err(_) => Host.assert!(False)
	}
	Host.assert!(input.selectors.get(count.to_u64() - 1) == Ok(1) and input.months.get(count.to_u64() - 1) == Ok(1) and input.texts.get(0) == Ok("19700101T000000"))
	{ bytes: "recurrence=declaration,budget=bounded\n".to_utf8(), work: [constructed - before, read - constructed, zero_after - read, tiny_after - zero_after, fixed_after - tiny_after, inspected - fixed_after] }
}
