app [main!] {
	time: "../../package/main.roc",
}
import Cases
import ZoneOracle

main! = |_args| {
	count = ZoneOracle.verify(Cases.fixtures, Cases.inputs, 2592)?
	echo!("PASS ${count.to_str()} oracle cases\n")
	Ok({})
}
