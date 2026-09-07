app [main!] { time: "../../package/main.roc" }
import CivilQueryChecks

main! = |args| {
	if (args.get(0) ?? "cycle") == "cycle" {
		count = CivilQueryChecks.cycle(args.get(1) ?? "")
		echo!("PASS ${count.to_str()} Gregorian days\n")
	} else {
		result = match CivilQueryChecks.query(args.get(0) ?? "") {
			Ok(value) => value
			Err(_) => crash "invalid oracle fixture input"
		}
		echo!("${result}\n")
	}
	Ok({})
}
