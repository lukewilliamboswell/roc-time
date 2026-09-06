app [main!] { fixture: "fixture.roc" }
import fixture.TimedOracle
import fixture.SmokeCases
main! = |_args| {
	count = TimedOracle.verify(SmokeCases.inputs)?
	echo!("PASS ${count.to_str()} oracle cases\n")
	Ok({})
}
