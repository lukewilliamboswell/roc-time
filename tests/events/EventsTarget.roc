import fuzz.Fuzz
import EventCase

EventsTarget := [].{
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
}
