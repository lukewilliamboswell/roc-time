import fuzz.Fuzz
import ArithmeticCase

ArithmeticTarget := [].{
	target = Fuzz.target({
		name: "arithmetic-v1",
		examples: [
			Fuzz.example({
				name: "lower-limit",
				revision: "1",
				make: || ArithmeticCase.{
					year: -2147483648,
					month: 1,
					day: 1,
					years: -2,
					months: -24,
					days: -60,
				},
			}),
			Fuzz.example({
				name: "upper-limit",
				revision: "1",
				make: || ArithmeticCase.{
					year: 2147483647,
					month: 12,
					day: 31,
					years: 2,
					months: 24,
					days: 60,
				},
			}),
			Fuzz.example({
				name: "leap-and-clamp",
				revision: "1",
				make: || ArithmeticCase.{
					year: 2000,
					month: 2,
					day: 31,
					years: 1,
					months: 1,
					days: -1,
				},
			}),
		],
		test: ArithmeticCase.check,
		show: Str.inspect,
	})
}
