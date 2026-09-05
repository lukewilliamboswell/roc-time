import fuzz.Fuzz

# Harness lifecycle fixture, deliberately separate from application examples.
LifecycleCheck :: [].{
	check : List(U8) -> Fuzz.Outcome
	check = |bytes| {
		for byte in bytes {
			if byte == 42 {
				crash "intentional lifecycle defect: byte 42 is allowed"
			}
		}
		Fuzz.keep
	}
}
