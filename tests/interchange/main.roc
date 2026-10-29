app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
	time: "../../package/main.roc",
}

import fuzz.Fuzz
import InterchangeCase

# Generated inputs exercise the invariant; these named cases pin its boundaries.
target = Fuzz.target({
	name: "interchange-v1",
	examples: [
		Fuzz.example({
			name: "lower-domain",
			revision: "1",
			make: || InterchangeCase.{
				year: 1900,
				month: 1,
				day: 0,
				precision: 0,
				qualifier: 0,
				seconds: 0,
				fraction: 0,
				digits: 0,
				offset: -1439,
			},
		}),
		Fuzz.example({
			name: "upper-domain",
			revision: "1",
			make: || InterchangeCase.{
				year: 2100,
				month: 12,
				day: 30,
				precision: 2,
				qualifier: 3,
				seconds: 86399,
				fraction: 999999,
				digits: 6,
				offset: 1439,
			},
		}),
		Fuzz.example({
			name: "leap-day",
			revision: "1",
			make: || InterchangeCase.{
				year: 2000,
				month: 2,
				day: 28,
				precision: 2,
				qualifier: 1,
				seconds: 43200,
				fraction: 123456,
				digits: 3,
				offset: 0,
			},
		}),
	],
	test: InterchangeCase.check,
	show: Str.inspect,
})
