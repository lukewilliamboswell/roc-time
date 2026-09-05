app [main!] {
	time: "../../package/main.roc",
}

import Cases
import GregorianOracle

main! = |_args| {
	count = GregorianOracle.verify(Cases.inputs, 4096)?
	echo!("PASS ${count.to_str()} oracle cases\n")
	Ok({})
}
