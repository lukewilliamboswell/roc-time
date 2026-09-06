app [main!] { time: "../../../package/main.roc" }
import time.Ixdtf

main! = |_args| {
	value = parse("1970-01-01T00:00:00Z")?
	snapshot = resolve(value)?
	_ = snapshot.source
	Ok({})
}

parse = |text| match Ixdtf.parse(text) {
	Ok(value) => Ok(value)
	Err(_) => Err(Exit(1))
}

resolve = |value| match Ixdtf.resolve(value, None) {
	Ok(snapshot) => Ok(snapshot)
	Err(_) => Err(Exit(1))
}
