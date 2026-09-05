app [main!] {
	time: "../package/main.roc",
}

import time.Time

main! = |_args| {
	echo!(Time.hello("World"))
	Ok({})
}

## The example greets whoever it is given.
expect Time.hello("Roc") == "Hello, Roc!"
