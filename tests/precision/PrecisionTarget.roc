import fuzz.Fuzz
import PrecisionCase

PrecisionTarget := [].{
	target = Fuzz.target({
		name: "precision-v1",
		examples: [
			Fuzz.example({
				name: "zero",
				revision: "1",
				make: || PrecisionCase.{
					a: 0,
					b: 0,
					nanos: 0,
				},
			}),
			Fuzz.example({
				name: "signed-limits",
				revision: "1",
				make: || PrecisionCase.{
					a: I64.lowest,
					b: I64.highest,
					nanos: 1999,
				},
			}),
			Fuzz.example({
				name: "positive-overflow",
				revision: "1",
				make: || PrecisionCase.{
					a: I64.highest,
					b: 1,
					nanos: 1001,
				},
			}),
			Fuzz.example({
				name: "negative-overflow",
				revision: "1",
				make: || PrecisionCase.{
					a: I64.lowest,
					b: -1,
					nanos: 999,
				},
			}),
		],
		test: PrecisionCase.check,
		show: Str.inspect,
	})
}
