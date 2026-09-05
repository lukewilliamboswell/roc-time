app [main!] {
	pf: platform "../../platform/main.roc",
	fixture: "../fixture.roc",
}
import fixture.Cases
import fixture.ZoneOracle

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	output = ZoneOracle.run_args(args, Cases.fixtures)
	{ bytes: output.to_utf8(), work: [1] }
}
