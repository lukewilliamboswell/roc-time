app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst",
	time: "../package/main.roc",
}

import cli.OsStr
import cli.Stdout
import time.Time

main! : List(OsStr) => Try({}, _)
main! = |args| {
	name = args.get(1).map_ok(OsStr.display) ?? "World"

	Stdout.line!(Time.hello(name))?

	Ok({})
}

## The example greets whoever it is given.
expect Time.hello("Roc") == "Hello, Roc!"
