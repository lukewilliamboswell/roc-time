app [main!] { time: "../../../package/main.roc" }
import time.Persistence
import time.PosixBoundary

main! = |_args| {
	stored = Persistence.new(PosixBoundary(PosixBoundary.from_microseconds(9007199254740993)))?
	_ = Json.to_str(stored)
	Ok({})
}
