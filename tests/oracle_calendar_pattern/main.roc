app [main!] { fixture: "fixture.roc" }
import fixture.PatternOracle
import fixture.SmokeCases
main! = |_args| {
	count = PatternOracle.verify(SmokeCases.inputs)?
	echo!("PASS ${count.to_str()} oracle cases\n")
	Ok({})
}
