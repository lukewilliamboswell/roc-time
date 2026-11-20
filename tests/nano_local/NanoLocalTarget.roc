import fuzz.Fuzz
import NanoLocalCase

NanoLocalTarget := [].{
	target = Fuzz.target({
		name: "nano-local-v1",
		examples: [
			Fuzz.example({ name: "lowest", revision: "1", make: || NanoLocalCase.{ number: I64.lowest } }),
			Fuzz.example({ name: "before-epoch", revision: "1", make: || NanoLocalCase.{ number: -1 } }),
			Fuzz.example({ name: "epoch", revision: "1", make: || NanoLocalCase.{ number: 0 } }),
			Fuzz.example({ name: "positive-even-tie", revision: "1", make: || NanoLocalCase.{ number: 2500 } }),
			Fuzz.example({ name: "negative-odd-tie", revision: "1", make: || NanoLocalCase.{ number: -1500 } }),
			Fuzz.example({ name: "highest", revision: "1", make: || NanoLocalCase.{ number: I64.highest } }),
		],
		test: NanoLocalCase.check,
		show: Str.inspect,
	})
}
