import time.GregorianDate
import time.CivilDay
import time.OffsetTimestamp
import time.PosixBoundary

Benchmark := [].{
	Input : { text : Str, timestamp : OffsetTimestamp, date : GregorianDate, fields : GregorianDate.Fields }
	prepare : List(Str) -> List(Input)
	prepare = |texts| texts.map(
		|text| {
			timestamp = match OffsetTimestamp.parse(text) {
				Ok(v) => v
				Err(_) => crash "validated benchmark timestamp"
			}
			date = OffsetTimestamp.parts(timestamp).date
			{ text, timestamp, date, fields: GregorianDate.to_fields(date) }
		},
	)
	run : List(Input), Str, U64 -> U64
	run = |data, mode, iterations| {
		var sum = 0.U64
		var i = 0.U64
		while i < iterations {
			v = match data.get(U64.rem_by(i, data.len())) {
				Ok(value) => value
				Err(_) => crash "nonempty benchmark corpus"
			}
			result = match mode {
				"construct" => date_sum(
					match GregorianDate.from_fields(v.fields) {
						Ok(value) => value
						Err(_) => crash "valid fields"
					},
				)
				"roundtrip" => date_sum(
					match GregorianDate.from_civil_day(GregorianDate.to_civil_day(v.date)) {
						Ok(value) => value
						Err(_) => crash "valid civil day"
					},
				)
				"add_days" => date_sum(
					match GregorianDate.from_civil_day(CivilDay.from_day_number(CivilDay.to_day_number(GregorianDate.to_civil_day(v.date)) + 17)) {
						Ok(value) => value
						Err(_) => crash "bounded date addition"
					},
				)
				"parse" => {
					parsed = match OffsetTimestamp.parse(v.text) {
						Ok(value) => value
						Err(_) => crash "valid timestamp"
					}
					boundary = match OffsetTimestamp.boundary(parsed) {
						Ok(value) => value
						Err(_) => crash "bounded timestamp"
					}
					I64.mod_by(PosixBoundary.to_microseconds(boundary), 1000000007).to_u64_wrap()
				}
				"format" => text_sum(OffsetTimestamp.to_text(v.timestamp))
				"end_to_end" => text_sum(
					OffsetTimestamp.to_text(
						match OffsetTimestamp.parse(v.text) {
							Ok(value) => value
							Err(_) => crash "valid timestamp"
						},
					),
				)
				_ => crash "unknown workload"
			}
			sum = sum + result
			i = i + 1
		}
		sum
	}
	verify = |data| Str.join_with(
		data.map(
			|v| {
				boundary = match OffsetTimestamp.boundary(v.timestamp) {
					Ok(value) => value
					Err(_) => crash "bounded timestamp"
				}
				"${CivilDay.to_day_number(GregorianDate.to_civil_day(v.date)).to_str()}|${PosixBoundary.to_microseconds(boundary).to_str()}|${OffsetTimestamp.to_text(v.timestamp)}"
			},
		),
		"\n",
	)
}

date_sum = |date| {
	fields = GregorianDate.to_fields(date)
	fields.year.to_u64_wrap() * 10000 + fields.month.to_u64() * 100 + fields.day.to_u64()
}

text_sum = |text| {
	var sum = 0.U64
	for byte in text.to_utf8() {
		sum = sum + byte.to_u64()
	}
	sum
}
