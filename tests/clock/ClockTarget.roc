import fuzz.Fuzz
import ClockCase

ClockTarget := [].{
	target = Fuzz.target({
		name: "clock-v1",
		examples: [
			Fuzz.example({
				name: "before-midnight",
				revision: "1",
				make: || ClockCase.{
					number: -1,
				},
			}),
			Fuzz.example({
				name: "midnight",
				revision: "1",
				make: || ClockCase.{
					number: 0,
				},
			}),
			Fuzz.example({
				name: "last-microsecond",
				revision: "1",
				make: || ClockCase.{
					number: 86399999999,
				},
			}),
			Fuzz.example({
				name: "exclusive-end",
				revision: "1",
				make: || ClockCase.{
					number: 86400000000,
				},
			}),
		],
		test: ClockCase.check,
		show: Str.inspect,
	})
}
