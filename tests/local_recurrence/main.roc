app [main!] { fixture: "fixture.roc" }
import fixture.LocalCases
main! = |_args| {
	count = LocalCases.verify_all({})?
	echo!("PASS ${count.to_str()} composed local recurrence cases\n")
	Ok({})
}
