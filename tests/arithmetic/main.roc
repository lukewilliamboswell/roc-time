app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
	time: "../../package/main.roc",
}

import fuzz.Fuzz
import "../fuzz/corpus/arithmetic/alternating" as retained_0 : List(U8)
import "../fuzz/corpus/arithmetic/ones" as retained_1 : List(U8)
import "../fuzz/corpus/arithmetic/ramp" as retained_2 : List(U8)
import "../fuzz/corpus/arithmetic/zero" as retained_3 : List(U8)
import ArithmeticCase

target = Fuzz.target({ examples: [Fuzz.saved({ name: "alternating", revision: "1", bytes: retained_0 }), Fuzz.saved({ name: "ones", revision: "1", bytes: retained_1 }), Fuzz.saved({ name: "ramp", revision: "1", bytes: retained_2 }), Fuzz.saved({ name: "zero", revision: "1", bytes: retained_3 })], name: "arithmetic-v1", test: ArithmeticCase.check, show: |input| Str.inspect(input) })
