app [main!] {}
Stamp :: { number : I64 }.{
	new : I64 -> Stamp
	new = |number| { number: number }
	is_eq : Stamp, Stamp -> Bool
	is_eq = |a, b| a.number == b.number
}

make = |n| {
	value = Stamp.new(n)
	{ values: [value, value], valid: Bool.True }
}

main! = |args| {
	left = make(args.len().to_i64_wrap())
	right = make(args.len().to_i64_wrap())
	echo!(Str.inspect(left.values == right.values and left.valid == right.valid))
	Ok({})
}
