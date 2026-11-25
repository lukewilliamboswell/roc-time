app [target] {
	arithmetic: "../arithmetic/package.roc",
	calendars: "../calendars/package.roc",
	clock: "../clock/package.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
	gregorian: "../gregorian/package.roc",
	nano_clock: "../nano_clock/package.roc",
	nano_local: "../nano_local/package.roc",
	offsets: "../offsets/package.roc",
	time: "../../package/main.roc",
}

import fuzz.Fuzz
import gregorian.GregorianTarget
import arithmetic.ArithmeticTarget
import calendars.CalendarsTarget
import clock.ClockTarget
import nano_clock.NanoClockTarget
import offsets.OffsetsTarget

import nano_local.NanoLocalTarget

target = Fuzz.suite([
	GregorianTarget.target,
	ArithmeticTarget.target,
	CalendarsTarget.target,
	ClockTarget.target,
	NanoClockTarget.target,
	OffsetsTarget.target,
	NanoLocalTarget.target,
])
