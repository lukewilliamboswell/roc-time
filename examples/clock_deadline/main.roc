app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	time: "../../package/main.roc",
}
import pf.Utc
import pf.Stdout
import Deadline

main! = |_args| {
	now = Deadline.acquire_positive_nanoseconds(Utc.now!())?
	record = Deadline.evaluate(now, "2030-01-01T00:00:00Z")?
	Stdout.line!(Deadline.encode(record))?
	Ok({})
}
