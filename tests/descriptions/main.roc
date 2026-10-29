app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
	time: "../../package/main.roc",
}

import fuzz.Fuzz
import DescriptionCase

# Generated inputs exercise the invariant; these named cases pin its boundaries.
target = Fuzz.target({
	name: "descriptions-v1",
	examples: [
		Fuzz.example({
			name: "start-gap",
			revision: "1",
			make: || DescriptionCase.{
				number: 0,
				digits: 1,
				gap: Bool.True,
			},
		}),
		Fuzz.example({
			name: "end-fold",
			revision: "1",
			make: || DescriptionCase.{
				number: 86399999999,
				digits: 6,
				gap: Bool.False,
			},
		}),
		Fuzz.example({
			name: "fractional-grid",
			revision: "1",
			make: || DescriptionCase.{
				number: 12345678,
				digits: 3,
				gap: Bool.True,
			},
		}),
	],
	test: DescriptionCase.check,
	show: Str.inspect,
})
