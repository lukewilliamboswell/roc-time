app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
	time: "../../package/main.roc",
}

import fuzz.Fuzz
import ZoneCase

# Generated inputs exercise the invariant; these named cases pin its boundaries.
target = Fuzz.target({
	name: "zones-v1",
	examples: [
		Fuzz.example({
			name: "forward-gap",
			revision: "1",
			make: || ZoneCase.{
				number: 1,
				first: -2,
				second: 2,
			},
		}),
		Fuzz.example({
			name: "backward-fold",
			revision: "1",
			make: || ZoneCase.{
				number: -1,
				first: 2,
				second: -2,
			},
		}),
		Fuzz.example({
			name: "unchanged-offset",
			revision: "1",
			make: || ZoneCase.{
				number: 0,
				first: 0,
				second: 0,
			},
		}),
		Fuzz.example({
			name: "domain-edge",
			revision: "1",
			make: || ZoneCase.{
				number: 7000000,
				first: -1,
				second: 1,
			},
		}),
	],
	test: ZoneCase.check,
	show: Str.inspect,
})
