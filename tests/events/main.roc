app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
	time: "../../package/main.roc",
}
import fuzz.Fuzz
import EventCase

# Generated inputs exercise the invariant; these named cases pin its boundaries.
target = Fuzz.target({
	name: "events-v1",
	examples: [
		Fuzz.example({
			name: "empty",
			revision: "1",
			make: || EventCase.{
				spans: [],
			},
		}),
		Fuzz.example({
			name: "duplicate-extents",
			revision: "1",
			make: || EventCase.{
				spans: [{ start: 0, width: 8 }, { start: 0, width: 8 }, { start: 4, width: 8 }],
			},
		}),
		Fuzz.example({
			name: "touching-and-disconnected",
			revision: "1",
			make: || EventCase.{
				spans: [{ start: 0, width: 2 }, { start: 2, width: 2 }, { start: 16, width: 1 }],
			},
		}),
	],
	test: EventCase.check,
	show: Str.inspect,
})
