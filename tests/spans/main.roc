app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	time: "../../package/main.roc",
}

import fuzz.Fuzz
import SpanCase

target = Fuzz.target({ name: "spans-v1", test: SpanCase.check, show: |input| Str.inspect(input) })
