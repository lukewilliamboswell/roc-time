import fuzz.Fuzz
import NanoClockCase

NanoClockTarget := [].{
	target = Fuzz.target({
		name: "nano-clock-v1",
		examples: [
			Fuzz.example({
				name: "before-midnight",
				revision: "1",
				make: || NanoClockCase.{
					number: -1,
				},
			}),
			Fuzz.example({
				name: "midnight",
				revision: "1",
				make: || NanoClockCase.{
					number: 0,
				},
			}),
			Fuzz.example({
				name: "nanosecond-after-noon",
				revision: "1",
				make: || NanoClockCase.{
					number: 43200000000001,
				},
			}),
			Fuzz.example({
				name: "tie-before-midnight",
				revision: "1",
				make: || NanoClockCase.{
					number: 86399999999500,
				},
			}),
			Fuzz.example({
				name: "last-nanosecond",
				revision: "1",
				make: || NanoClockCase.{
					number: 86399999999999,
				},
			}),
			Fuzz.example({
				name: "exclusive-end",
				revision: "1",
				make: || NanoClockCase.{
					number: 86400000000000,
				},
			}),
		],
		test: NanoClockCase.check,
		show: Str.inspect,
	})
}
