app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
	time: "../../package/main.roc",
}

import fuzz.Fuzz
import CalendarCase

# Generated inputs exercise the invariant; these named cases pin its boundaries.
target = Fuzz.target({
	name: "calendars-v1",
	examples: [
		Fuzz.example({
			name: "provider-start",
			revision: "1",
			make: || CalendarCase.{
				number: -784369121962,
			},
		}),
		Fuzz.example({
			name: "provider-end",
			revision: "1",
			make: || CalendarCase.{
				number: 784367682901,
			},
		}),
		Fuzz.example({
			name: "shared-epoch",
			revision: "1",
			make: || CalendarCase.{
				number: 0,
			},
		}),
	],
	test: CalendarCase.check,
	show: Str.inspect,
})
