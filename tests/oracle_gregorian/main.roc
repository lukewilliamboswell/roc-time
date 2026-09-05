app [main!] { fixture: "fixture.roc" }
import fixture.GregorianOracle
import fixture.SmokeCases
main! = |_args| {
	count = GregorianOracle.verify(SmokeCases.inputs, 128)?
	echo!("PASS ${count.to_str()} oracle cases\n")
	Ok({})
}
