app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
}

import fuzz.Fuzz
import "../fuzz/corpus/lifecycle_fixed/byte-42" as retained_0 : List(U8)
import LifecycleCheck

target = Fuzz.target_with({ examples: [Fuzz.saved({ name: "byte-42", revision: "1", bytes: retained_0 })], name: "lifecycle-fixed-v1", generator: Fuzz.raw_bytes, test: LifecycleCheck.check, show: |bytes| Str.inspect(bytes) })
