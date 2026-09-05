app [main!] {
	time: "../../package/main.roc",
}

import time.GregorianDate

# R05/R15: scalar construction versus coordinate conversion, years 1970..9999,
# months 1..12 and days 1..28. Runtime inputs and observable checksum keep the
# loop measurable; the Python runner validates output outside the timed process.

main! = |args| {
	iterations = U64.from_str(args.get(0) ?? "1000000") ?? 1000000
	mode = args.get(1) ?? "fields"
	var $i = 0.U64
	var $checksum = 0.I64
	while $i < iterations {
		year = 1970.I64 + (($i * 37) % 8030).to_i64_wrap()
		month = ((($i * 17) % 12) + 1).to_u8_wrap()
		day = ((($i * 13) % 28) + 1).to_u8_wrap()
		date = GregorianDate.from_fields({ year, month, day })?
		observed = if mode == "roundtrip" {
			GregorianDate.from_civil_day(GregorianDate.to_civil_day(date))?
		} else {
			date
		}
		fields = GregorianDate.to_fields(observed)
		$checksum = $checksum + fields.year + U8.to_i64(fields.month) + U8.to_i64(fields.day)
		$i = $i + 1
	}
	echo!($checksum.to_str())
	Ok({})
}
