import fuzz.Fuzz
import GregorianCase

GregorianTarget := [].{
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
}
