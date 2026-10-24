app [main!] {}
import Seen
main! = |args| {
	echo!(Str.inspect(Seen.contains_inserted(args.len())))
	Ok({})
}
