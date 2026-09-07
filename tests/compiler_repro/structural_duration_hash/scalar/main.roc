app [main!] { time: "../../../../package/main.roc" }
import HashKey

main! = |args| {
	key = HashKey.new(I64.from_str(args.get(0) ?? "1") ?? 1)
	echo!("${Str.inspect(Dict.get(Dict.insert(Dict.empty(), key, 73.U8), key))}\n")
	Ok({})
}
