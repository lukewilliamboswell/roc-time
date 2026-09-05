app [main!] {
	time: "../../../package/main.roc",
}
import time.EventCollection

main! = |_args| {
	forged : EventCollection(U64)
	forged = []
	_count = EventCollection.event_count(forged)
	Ok({})
}
