app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
	time: "../../package/main.roc",
}

import fuzz.Fuzz
import OffsetCase

# Generated inputs exercise the invariant; these named cases pin its boundaries.
target = Fuzz.target({
	name: "offsets-v1",
	examples: [
		Fuzz.example({
			name: "negative-limits",
			revision: "1",
			make: || OffsetCase.{
				number: I64.lowest,
				seconds: I32.lowest,
			},
		}),
		Fuzz.example({
			name: "positive-limits",
			revision: "1",
			make: || OffsetCase.{
				number: I64.highest,
				seconds: I32.highest,
			},
		}),
		Fuzz.example({
			name: "utc-epoch",
			revision: "1",
			make: || OffsetCase.{
				number: 0,
				seconds: 0,
			},
		}),
	],
	test: OffsetCase.check,
	show: Str.inspect,
})
