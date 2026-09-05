app [main!] {
	time: "../../package/main.roc",
}

import Cases
import JulianOracle

main! = |_args| {
	count = JulianOracle.verify(Cases.inputs, 4096)?
	echo!("PASS ${count.to_str()} oracle cases\n")
	Ok({})
}
