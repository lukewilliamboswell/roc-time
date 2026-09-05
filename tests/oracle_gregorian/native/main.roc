app [main!] {
	pf: platform "../../platform/main.roc",
	fixture: "../fixture.roc",
}
import fixture.GregorianOracle

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	result = GregorianOracle.run_args(args)
	{ bytes: result.to_utf8(), work: [1] }
}
