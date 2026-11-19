import fuzz.Fuzz
import CoverageCase
import "../fuzz/corpus/coverage/subtraction-inner-loop-stop" as regression_0 : List(U8)

CoverageTarget := [].{
	target = Fuzz.target({
		name: "coverage-v2",
		examples: [
			Fuzz.saved({
				name: "subtraction-inner-loop-stop",
				revision: "1",
				bytes: regression_0,
			}),
			Fuzz.example({
				name: "empty",
				revision: "1",
				make: || CoverageCase.{
					left: [],
					right: [],
					window: { lo: -8, width: 17 },
				},
			}),
			Fuzz.example({
				name: "duplicates-and-overlap",
				revision: "1",
				make: || CoverageCase.{
					left: [{ lo: -3, width: 5 }, { lo: -3, width: 5 }],
					right: [{ lo: 1, width: 4 }],
					window: { lo: -8, width: 17 },
				},
			}),
			Fuzz.example({
				name: "touching-and-disconnected",
				revision: "1",
				make: || CoverageCase.{
					left: [{ lo: -8, width: 2 }, { lo: -6, width: 2 }],
					right: [{ lo: 4, width: 3 }],
					window: { lo: -8, width: 17 },
				},
			}),
		],
		test: CoverageCase.check,
		show: Str.inspect,
	})
}
