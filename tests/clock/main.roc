app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
	time: "../../package/main.roc",
}

import fuzz.Fuzz
import ClockCase

# Generated inputs exercise the invariant; these named cases pin its boundaries.
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
