app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
	local: "../local_recurrence/fixture.roc",
	time: "../../package/main.roc",
}
import fuzz.Fuzz
import "../fuzz/corpus/recurrence/alternating" as retained_0 : List(U8)
import "../fuzz/corpus/recurrence/boundary-exclusion-merge-buffer" as retained_1 : List(U8)
import "../fuzz/corpus/recurrence/local-gap-boundary-exclusion" as retained_2 : List(U8)
import "../fuzz/corpus/recurrence/ones" as retained_3 : List(U8)
import "../fuzz/corpus/recurrence/ramp" as retained_4 : List(U8)
import "../fuzz/corpus/recurrence/zero" as retained_5 : List(U8)
import RecurrenceCase
target = Fuzz.target({ examples: [Fuzz.saved({ name: "alternating", revision: "1", bytes: retained_0 }), Fuzz.saved({ name: "boundary-exclusion-merge-buffer", revision: "1", bytes: retained_1 }), Fuzz.saved({ name: "local-gap-boundary-exclusion", revision: "1", bytes: retained_2 }), Fuzz.saved({ name: "ones", revision: "1", bytes: retained_3 }), Fuzz.saved({ name: "ramp", revision: "1", bytes: retained_4 }), Fuzz.saved({ name: "zero", revision: "1", bytes: retained_5 })], name: "recurrence-v1", test: RecurrenceCase.check, show: |input| Str.inspect(input) })
