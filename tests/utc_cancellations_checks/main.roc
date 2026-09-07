app [main!] {
	roc: "nightly-2026-09-06-d85e877",
	time: "../../package/main.roc",
}
import UtcCancellationChecks

main! = |args| {
	UtcCancellationChecks.run(args.get(0) ?? "")
	echo!("PASS UTC cancellation source identity, collisions and RFC interchange checks\n")
	Ok({})
}
