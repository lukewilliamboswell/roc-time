app [main!] { time: "../../../package/main.roc" }
import time.Evidence.Interval as IntervalEvidence
import time.Coverage
import time.PosixBoundary
main! = |_args| {
	evidence = IntervalEvidence.independent({ starts: [PosixBoundary.from_microseconds(0)], ends: [PosixBoundary.from_microseconds(1)] })?
	_invalid = Coverage.contains(evidence, PosixBoundary.from_microseconds(0))
	Ok({})
}
