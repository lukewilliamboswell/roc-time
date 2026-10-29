app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
	time: "../../package/main.roc",
}

import fuzz.Fuzz
import "../fuzz/corpus/spans/alternating" as retained_0 : List(U8)
import "../fuzz/corpus/spans/ones" as retained_1 : List(U8)
import "../fuzz/corpus/spans/pattern64-ascending" as retained_2 : List(U8)
import "../fuzz/corpus/spans/pattern64-ones" as retained_3 : List(U8)
import "../fuzz/corpus/spans/pattern64-zeros" as retained_4 : List(U8)
import "../fuzz/corpus/spans/ramp" as retained_5 : List(U8)
import "../fuzz/corpus/spans/relation-after" as retained_6 : List(U8)
import "../fuzz/corpus/spans/relation-before" as retained_7 : List(U8)
import "../fuzz/corpus/spans/relation-contains" as retained_8 : List(U8)
import "../fuzz/corpus/spans/relation-during" as retained_9 : List(U8)
import "../fuzz/corpus/spans/relation-equal" as retained_10 : List(U8)
import "../fuzz/corpus/spans/relation-finished_by" as retained_11 : List(U8)
import "../fuzz/corpus/spans/relation-finishes" as retained_12 : List(U8)
import "../fuzz/corpus/spans/relation-meets" as retained_13 : List(U8)
import "../fuzz/corpus/spans/relation-met_by" as retained_14 : List(U8)
import "../fuzz/corpus/spans/relation-overlapped_by" as retained_15 : List(U8)
import "../fuzz/corpus/spans/relation-overlaps" as retained_16 : List(U8)
import "../fuzz/corpus/spans/relation-started_by" as retained_17 : List(U8)
import "../fuzz/corpus/spans/relation-starts" as retained_18 : List(U8)
import "../fuzz/corpus/spans/zero" as retained_19 : List(U8)
import SpanCase

target = Fuzz.target({ examples: [Fuzz.saved({ name: "alternating", revision: "1", bytes: retained_0 }), Fuzz.saved({ name: "ones", revision: "1", bytes: retained_1 }), Fuzz.saved({ name: "pattern64-ascending", revision: "1", bytes: retained_2 }), Fuzz.saved({ name: "pattern64-ones", revision: "1", bytes: retained_3 }), Fuzz.saved({ name: "pattern64-zeros", revision: "1", bytes: retained_4 }), Fuzz.saved({ name: "ramp", revision: "1", bytes: retained_5 }), Fuzz.saved({ name: "relation-after", revision: "1", bytes: retained_6 }), Fuzz.saved({ name: "relation-before", revision: "1", bytes: retained_7 }), Fuzz.saved({ name: "relation-contains", revision: "1", bytes: retained_8 }), Fuzz.saved({ name: "relation-during", revision: "1", bytes: retained_9 }), Fuzz.saved({ name: "relation-equal", revision: "1", bytes: retained_10 }), Fuzz.saved({ name: "relation-finished_by", revision: "1", bytes: retained_11 }), Fuzz.saved({ name: "relation-finishes", revision: "1", bytes: retained_12 }), Fuzz.saved({ name: "relation-meets", revision: "1", bytes: retained_13 }), Fuzz.saved({ name: "relation-met_by", revision: "1", bytes: retained_14 }), Fuzz.saved({ name: "relation-overlapped_by", revision: "1", bytes: retained_15 }), Fuzz.saved({ name: "relation-overlaps", revision: "1", bytes: retained_16 }), Fuzz.saved({ name: "relation-started_by", revision: "1", bytes: retained_17 }), Fuzz.saved({ name: "relation-starts", revision: "1", bytes: retained_18 }), Fuzz.saved({ name: "zero", revision: "1", bytes: retained_19 })], name: "spans-v1", test: SpanCase.check, show: |input| Str.inspect(input) })
