app [target] {
	descriptions: "../descriptions/package.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.7.0/HBigHQhVZWEF2EkLxpYK35u8P6UNsAmPYxpNFTxXK1Br.tar.zst",
	interchange: "../interchange/package.roc",
	patterns: "../patterns/package.roc",
	recurrence: "../recurrence/package.roc",
	time: "../../package/main.roc",
	zones: "../zones/package.roc",
}

import fuzz.Fuzz
import zones.ZonesTarget
import patterns.PatternsTarget
import recurrence.RecurrenceTarget
import descriptions.DescriptionsTarget
import interchange.InterchangeTarget

target = Fuzz.suite([
	ZonesTarget.target,
	PatternsTarget.target,
	RecurrenceTarget.target,
	DescriptionsTarget.target,
	InterchangeTarget.target,
])
