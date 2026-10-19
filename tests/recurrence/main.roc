app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	local: "../local_recurrence/fixture.roc",
	time: "../../package/main.roc",
}
import fuzz.Fuzz
import RecurrenceCase
target = Fuzz.target({ name: "recurrence-v1", test: RecurrenceCase.check, show: |input| Str.inspect(input) })
