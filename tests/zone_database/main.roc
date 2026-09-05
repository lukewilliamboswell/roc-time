app [main!] {
	time: "../../package/main.roc",
	zones: "../../tzdb/package/main.roc",
}
import ProviderCase

main! = |args| {
	ProviderCase.verify("Unknown-${args.len().to_str()}")?
	echo!("PASS zone database\n")
	Ok({})
}
