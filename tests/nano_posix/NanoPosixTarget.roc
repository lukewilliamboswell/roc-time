import fuzz.Fuzz
import NanoPosixCase

NanoPosixTarget := [].{
	target = Fuzz.target({
		name: "nano-posix-v1",
		examples: [
			Fuzz.example({ name: "lowest", revision: "1", make: || NanoPosixCase.{ number: I64.lowest } }),
			Fuzz.example({ name: "before-epoch", revision: "1", make: || NanoPosixCase.{ number: -1 } }),
			Fuzz.example({ name: "epoch", revision: "1", make: || NanoPosixCase.{ number: 0 } }),
			Fuzz.example({ name: "positive-even-tie", revision: "1", make: || NanoPosixCase.{ number: 2500 } }),
			Fuzz.example({ name: "negative-odd-tie", revision: "1", make: || NanoPosixCase.{ number: -1500 } }),
			Fuzz.example({ name: "highest", revision: "1", make: || NanoPosixCase.{ number: I64.highest } }),
		],
		test: NanoPosixCase.check,
		show: Str.inspect,
	})
}
