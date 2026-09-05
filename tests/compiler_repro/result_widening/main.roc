app [main!] { time: "../../../package/main.roc" }
import time.GregorianDate
import Probe
main! = |_args| {
	date = GregorianDate.from_fields({ year: 2025, month: 1, day: 31 })?
	echo!(Str.inspect(Probe.identity(date)))
	Ok({})
}
