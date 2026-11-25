app [target] {
	descriptions: "../descriptions/package.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
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
