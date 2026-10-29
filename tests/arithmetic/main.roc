app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
	time: "../../package/main.roc",
}

import fuzz.Fuzz
import ArithmeticCase

# Generated inputs exercise the invariant; these named cases pin its boundaries.
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
