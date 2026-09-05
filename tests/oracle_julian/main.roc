app [main!] { fixture: "fixture.roc" }
import fixture.JulianOracle
import fixture.SmokeCases
main! = |_args| {
	count = JulianOracle.verify(SmokeCases.inputs, 128)?
	echo!("PASS ${count.to_str()} oracle cases\n")
	Ok({})
}
