import fuzz.Fuzz
import OffsetCase

OffsetsTarget := [].{
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
}
