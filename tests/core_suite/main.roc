app [target] {
	coverage: "../coverage/package.roc",
	events: "../events/package.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
	nano_posix: "../nano_posix/package.roc",
	precision: "../precision/package.roc",
	retention: "../retention/package.roc",
	spans: "../spans/package.roc",
	time: "../../package/main.roc",
}

import fuzz.Fuzz
import precision.PrecisionTarget
import spans.SpansTarget
import coverage.CoverageTarget
import events.EventsTarget
import retention.RetentionTarget

import nano_posix.NanoPosixTarget

target = Fuzz.suite([
	PrecisionTarget.target,
	SpansTarget.target,
	CoverageTarget.target,
	RetentionTarget.target,
	EventsTarget.target,
	NanoPosixTarget.target,
])
