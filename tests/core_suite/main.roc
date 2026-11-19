app [target] {
	coverage: "../coverage/package.roc",
	events: "../events/package.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.7.0/HBigHQhVZWEF2EkLxpYK35u8P6UNsAmPYxpNFTxXK1Br.tar.zst",
	precision: "../precision/package.roc",
	spans: "../spans/package.roc",
	time: "../../package/main.roc",
}

import fuzz.Fuzz
import precision.PrecisionTarget
import spans.SpansTarget
import coverage.CoverageTarget
import events.EventsTarget

target = Fuzz.suite([
	PrecisionTarget.target,
	SpansTarget.target,
	CoverageTarget.target,
	EventsTarget.target,
])
