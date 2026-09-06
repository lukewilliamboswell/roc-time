app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.Explanation
import DeclarationFixture

# R01/R11/R14/R15: a huge nominal day count is retained, not enumerated or
# multiplied into a coordinate duration. Construction precedes scopes; repeated
# fact reads, rendering and inspection have separate allocation observations.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	kind = U8.from_str(args.get(1) ?? "4") ?? 4
	days = I64.from_str(args.get(2) ?? "9223372036854775807") ?? 9223372036854775807
	local = (args.get(3) ?? "local") == "local"
	ceiling = U64.from_str(args.get(4) ?? "65536") ?? 65536
	Host.assert!(kind <= 4 and (days == 1 or days == I64.highest))
	source = DeclarationFixture.source(kind, days, local)
	before = Host.allocated_bytes!({})
	explanation = Explanation.new(source)
	var reads = 0.U32
	while reads < 100000 {
		match Explanation.fact_at(explanation, 0) {
			Item(fact) => Host.assert!(DeclarationFixture.matches(fact, kind, days, local))
			End => Host.assert!(False)
		}
		reads = reads + 1
	}
	read_after = Host.allocated_bytes!({})
	Host.assert!(read_after == before)
	empty = Explanation.plain(explanation, { max_facts: 0, max_utf8_bytes: 65536 })
	no_bytes = Explanation.plain(explanation, { max_facts: 100, max_utf8_bytes: 0 })
	zero_after = Host.allocated_bytes!({})
	Host.assert!(zero_after == read_after and empty.visited_facts == 0 and no_bytes.visited_facts == 0 and empty.text == "" and no_bytes.text == "")
	tiny = Explanation.plain(explanation, { max_facts: 1, max_utf8_bytes: 3 })
	tiny_after = Host.allocated_bytes!({})
	Host.assert!(tiny_after - zero_after <= ceiling and tiny.status == Limited(ByteLimit) and tiny.text == "..." and tiny.visited_facts == 1)
	full = Explanation.plain(explanation, { max_facts: 100, max_utf8_bytes: 65536 })
	full_after = Host.allocated_bytes!({})
	Host.assert!(full_after - tiny_after <= ceiling and full.status == Complete and full.visited_facts == full.total_facts and full.text.count_utf8_bytes() < 4096)
	if local and (kind == 1 or kind >= 3) {
		Host.assert!(full.text.contains("requires explicit zone context"))
	}
	if kind == 2 {
		Host.assert!(full.text.contains("requires a start"))
	}
	if kind == 4 {
		Host.assert!(!full.text.contains("requires a start") and full.text.contains("no end has been computed"))
	}
	summary = DeclarationFixture.inspect(source)
	inspected = Host.allocated_bytes!({})
	Host.assert!(inspected - full_after <= ceiling and summary.count_utf8_bytes() <= 256)
	{ bytes: "facts=preserved,render=bounded,end=not-invented\n".to_utf8(), work: [read_after - before, zero_after - read_after, tiny_after - zero_after, full_after - tiny_after, inspected - full_after] }
}
