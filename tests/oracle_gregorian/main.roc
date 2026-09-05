app [main!] {
	time: "../../package/main.roc",
}

import Cases
import GregorianOracle

main! = |_args| {
	for input in Cases.inputs {
		echo!("${GregorianOracle.observe(input)}\n")
	}
	Ok({})
}
