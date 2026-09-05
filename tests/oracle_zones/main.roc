app [main!] {
	fixture: "fixture.roc",
}
import fixture.Cases
import fixture.ZoneOracle

main! = |_args| {
	count = ZoneOracle.verify(Cases.fixtures, Cases.inputs, Cases.inputs.len())?
	echo!("PASS ${count.to_str()} oracle cases\n")
	Ok({})
}
