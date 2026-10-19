app [main!] { fixture: "fixture.roc" }
import fixture.LocalCases
# Independently modeled expectations only. Never invoke from normal replay.
main! = |_args| {
	echo!(LocalCases.snapshot(Bool.True))
	Ok({})
}
