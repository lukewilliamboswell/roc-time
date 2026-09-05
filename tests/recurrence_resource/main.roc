app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.CalendarPattern
import time.DateRecurrence
import time.GregorianDate

# R12/R15: runtime horizon, shared cursor, bounded prefix. Hundreds of billions
# of logical days must never become an eagerly materialized intermediate list.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	year = I64.from_str(args.get(1) ?? "2000000000") ?? 2000000000
	ceiling = U64.from_str(args.get(2) ?? "4096") ?? 4096
	start_year = I64.from_str(args.get(3) ?? "2000") ?? 2000
	anchor = fixture_date(start_year, 1)
	end = match GregorianDate.from_fields({ year, month: 1, day: 1 }) {
		Ok(value) => value
		Err(_) => crash "fixture horizon"
	}
	rule = match DateRecurrence.new(anchor, { pattern: CalendarPattern.defaults(Daily), termination: Forever, by_set_pos: [], inclusions: [], exclusions: [] }) {
		Ok(value) => value
		Err(_) => crash "fixture rule"
	}
	cursor = match DateRecurrence.cursor(rule, { start: anchor, end }) {
		Ok(value) => value
		Err(_) => crash "fixture cursor"
	}
	before = Host.allocated_bytes!({})
	stream = DateRecurrence.Cursor.chunks(cursor, { max_steps: 8, max_buffered: 1, max_occurrences: 1 })
	constructed = Host.allocated_bytes!({})
	Host.assert!(constructed - before <= ceiling)
	count = stream.take_first(1).fold(
		0.U64,
		|_, result| match result {
			Err(_) => crash "prefix failed"
			Ok(batch) => {
				if batch.dates != [anchor] or batch.steps > 8 {
					crash "incorrect prefix"
				}
				batch.dates.len()
			}
		},
	)
	consumed = Host.allocated_bytes!({})
	Host.assert!(count == 1 and consumed - constructed <= ceiling)
	folded = match DateRecurrence.Cursor.fold(
		cursor,
		{ max_steps: 8, max_buffered: 1, max_occurrences: 1 },
		0.U64,
		|n, date| {
			if date != anchor {
				crash "incorrect stopped date"
			}
			Stop(n + 1)
		},
	) {
		Ok(value) => value
		Err(_) => crash "stopping fold failed"
	}
	after = Host.allocated_bytes!({})
	Host.assert!(folded.value == 1 and folded.occurrences == 1 and after - consumed <= ceiling)
	match folded.status {
		Stopped(rest) => {
			next = match DateRecurrence.Cursor.next(rest, { max_steps: 8, max_buffered: 1 }) {
				Ok(value) => value
				Err(_) => crash "resume failed"
			}
			match next.status {
				Item(item) => {
					expected = fixture_date(start_year, 2)
					Host.assert!(item.date == expected)
				}
				_ => Host.assert!(False)
			}
		}
		_ => Host.assert!(False)
	}
	# Query far after DTSTART: budget candidate work even when no result is
	# nearby. Searching for the first visible date must not hide a long scan.
	later = fixture_date(year - 1, 2)
	delayed = match DateRecurrence.cursor(rule, { start: later, end }) {
		Ok(value) => value
		Err(_) => crash "delayed cursor"
	}
	search_before = Host.allocated_bytes!({})
	searched = match DateRecurrence.Cursor.next(delayed, { max_steps: 1, max_buffered: 1 }) {
		Ok(value) => value
		Err(_) => crash "bounded search failed"
	}
	search_after = Host.allocated_bytes!({})
	Host.assert!(searched.steps == 1 and search_after - search_before <= ceiling)
	match searched.status {
		Limited(progress) => Host.assert!(progress.reason == WorkLimit)
		_ => Host.assert!(False)
	}
	# Consume the entire zero-work stream. It must expose one incomplete
	# outcome, then stop; endlessly retrying its cursor would hit the deadline.
	zero_before = Host.allocated_bytes!({})
	zero_count = DateRecurrence.Cursor.chunks(delayed, { max_steps: 0, max_buffered: 1, max_occurrences: 1 }).fold(
		0.U64,
		|n, result| {
			match result {
				Ok(batch) => {
					if batch.steps != 0 or batch.dates != [] {
						crash "zero-work cursor advanced"
					}
					match batch.status {
						Limited(progress) => if progress.reason != WorkLimit {
							crash "wrong zero-work outcome"
						}
						Complete => crash "zero-work query falsely completed"
					}
				}
				Err(_) => crash "zero-work stream failed"
			}
			n + 1
		},
	)
	zero_after = Host.allocated_bytes!({})
	Host.assert!(zero_count == 1 and zero_after - zero_before <= ceiling)
	{ bytes: "prefix=1,resume=2,limited=1,zero=1\n".to_utf8(), work: [constructed - before, consumed - constructed, after - consumed, search_after - search_before, zero_after - zero_before] }
}

fixture_date = |year, day| match GregorianDate.from_fields({ year, month: 1, day }) {
	Ok(value) => value
	Err(_) => crash "fixture date"
}
