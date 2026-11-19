app [target] {
	arithmetic: "../arithmetic/package.roc",
	calendars: "../calendars/package.roc",
	clock: "../clock/package.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.7.0/HBigHQhVZWEF2EkLxpYK35u8P6UNsAmPYxpNFTxXK1Br.tar.zst",
	gregorian: "../gregorian/package.roc",
	offsets: "../offsets/package.roc",
	time: "../../package/main.roc",
}

import fuzz.Fuzz
import gregorian.GregorianTarget
import arithmetic.ArithmeticTarget
import calendars.CalendarsTarget
import clock.ClockTarget
import offsets.OffsetsTarget

target = Fuzz.suite([
	GregorianTarget.target,
	ArithmeticTarget.target,
	CalendarsTarget.target,
	ClockTarget.target,
	OffsetsTarget.target,
])
