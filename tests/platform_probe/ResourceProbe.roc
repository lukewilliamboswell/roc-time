import time.PosixBoundary

## R01/R15: runtime scalar comparison, with its result consumed by the host.
ResourceProbe := [].{
	compare : I64, I64 -> U64
	compare = |a, b| match PosixBoundary.order_relative_to(PosixBoundary.from_microseconds(a), PosixBoundary.from_microseconds(b)) {
		Before => 0
		Same => 1
		After => 2
	}
}
