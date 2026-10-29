app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
	time: "../../package/main.roc",
}
import fuzz.Fuzz
import PatternCase

# Generated inputs exercise the invariant; these named cases pin its boundaries.
target = Fuzz.target({
	name: "patterns-v1",
	examples: [
		Fuzz.example({
			name: "invalid-zero-selector",
			revision: "1",
			make: || PatternCase.{
				year: 2000,
				month: 1,
				interval: 1,
				index: 0,
				weekday: 0,
				ordinal: 0,
				month_day: 0,
			},
		}),
		Fuzz.example({
			name: "last-weekday",
			revision: "1",
			make: || PatternCase.{
				year: 0,
				month: 2,
				interval: 3,
				index: 6,
				weekday: 6,
				ordinal: -1,
				month_day: -1,
			},
		}),
		Fuzz.example({
			name: "provider-end",
			revision: "1",
			make: || PatternCase.{
				year: 2147483647,
				month: 12,
				interval: 3,
				index: 6,
				weekday: 0,
				ordinal: 1,
				month_day: 31,
			},
		}),
	],
	test: PatternCase.check,
	show: Str.inspect,
})
