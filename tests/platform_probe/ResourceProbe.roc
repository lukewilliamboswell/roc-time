import time.PosixBoundary

## R01/R15: runtime scalar comparison, with its result consumed by the host.
ResourceProbe := [].{
	compare : I64, I64 -> U64
	compare = |a, b| match PosixBoundary.compare(PosixBoundary.from_microseconds(a), PosixBoundary.from_microseconds(b)) {
		LT => 0
		EQ => 1
		GT => 2
	}
}
