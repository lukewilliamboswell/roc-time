app [main!] {
	pf: platform "../../platform/main.roc",
	fixture: "../fixture.roc",
}
import fixture.JulianOracle

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	result = JulianOracle.run_args(args)
	{ bytes: result.to_utf8(), work: [1] }
}
