app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
}

import fuzz.Fuzz
import "../fuzz/corpus/lifecycle_fixed/byte-42" as retained_0 : List(U8)
import LifecycleCheck

target = Fuzz.target_with({ examples: [Fuzz.saved({ name: "byte-42", revision: "1", bytes: retained_0 })], name: "lifecycle-fixed-v1", generator: Fuzz.raw_bytes, test: LifecycleCheck.check, show: |bytes| Str.inspect(bytes) })
