app [main!] { fixture: "fixture.roc" }
import fixture.DateOracle
import fixture.SmokeCases
main! = |_args| {
	count = DateOracle.verify(SmokeCases.inputs)?
	echo!("PASS ${count.to_str()} oracle cases\n")
	Ok({})
}
