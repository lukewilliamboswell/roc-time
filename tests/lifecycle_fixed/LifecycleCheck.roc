import fuzz.Fuzz

# Harness lifecycle fixture, deliberately separate from application examples.
LifecycleCheck :: [].{
	check : List(U8) -> Fuzz.Outcome
	check = |_bytes| Fuzz.keep
}
