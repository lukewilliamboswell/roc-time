app [main!] {
	time: "../../package/main.roc",
}

import NanosecondColumns

main! : List(Str) => Try({}, _)
main! = |_args| {
	report = NanosecondColumns.report({
		opening: ClockNanoseconds(43200000000001),
		closing: NullClock,
		zoned: { nanoseconds: -1, timezone: "Europe/Paris" },
		local: -1,
		displacement: -1500,
	})?
	echo!(report)
	Ok({})
}
