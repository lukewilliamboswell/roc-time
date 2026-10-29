app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
	time: "../../package/main.roc",
}

import fuzz.Fuzz
import "../fuzz/corpus/precision/alternating" as retained_0 : List(U8)
import "../fuzz/corpus/precision/ones" as retained_1 : List(U8)
import "../fuzz/corpus/precision/pattern64-ascending" as retained_2 : List(U8)
import "../fuzz/corpus/precision/pattern64-ones" as retained_3 : List(U8)
import "../fuzz/corpus/precision/pattern64-zeros" as retained_4 : List(U8)
import "../fuzz/corpus/precision/ramp" as retained_5 : List(U8)
import "../fuzz/corpus/precision/zero" as retained_6 : List(U8)
import PrecisionCase

target = Fuzz.target({ examples: [Fuzz.saved({ name: "alternating", revision: "1", bytes: retained_0 }), Fuzz.saved({ name: "ones", revision: "1", bytes: retained_1 }), Fuzz.saved({ name: "pattern64-ascending", revision: "1", bytes: retained_2 }), Fuzz.saved({ name: "pattern64-ones", revision: "1", bytes: retained_3 }), Fuzz.saved({ name: "pattern64-zeros", revision: "1", bytes: retained_4 }), Fuzz.saved({ name: "ramp", revision: "1", bytes: retained_5 }), Fuzz.saved({ name: "zero", revision: "1", bytes: retained_6 })], name: "precision-v1", test: PrecisionCase.check, show: |input| Str.inspect(input) })
