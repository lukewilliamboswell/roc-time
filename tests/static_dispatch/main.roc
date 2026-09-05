app [main!] {
	time: "../../package/main.roc",
}
import DispatchChecks

main! = |_args| {
	DispatchChecks.run({})?
	echo!("PASS static dispatch\n")
	Ok({})
}
