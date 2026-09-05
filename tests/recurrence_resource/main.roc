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
	{ bytes: "prefix=1,resume=2\n".to_utf8(), work: [constructed - before, consumed - constructed, after - consumed] }
}

fixture_date = |year, day| match GregorianDate.from_fields({ year, month: 1, day }) {
	Ok(value) => value
	Err(_) => crash "fixture date"
}
