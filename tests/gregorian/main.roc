app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
	time: "../../package/main.roc",
}

import fuzz.Fuzz
import GregorianCase

# Generated inputs exercise the invariant; these named cases pin its boundaries.
target = Fuzz.target({
	name: "gregorian-v1",
	examples: [
		Fuzz.example({
			name: "provider-start",
			revision: "1",
			make: || GregorianCase.{
				number: -784353015833,
				raw: 0,
				month: 0,
				day: 0,
			},
		}),
		Fuzz.example({
			name: "provider-end",
			revision: "1",
			make: || GregorianCase.{
				number: 784351576776,
				raw: U64.highest,
				month: 255,
				day: 255,
			},
		}),
		Fuzz.example({
			name: "epoch",
			revision: "1",
			make: || GregorianCase.{
				number: 0,
				raw: 1970,
				month: 2,
				day: 29,
			},
		}),
	],
	test: GregorianCase.check,
	show: Str.inspect,
})
