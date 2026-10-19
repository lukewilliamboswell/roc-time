app [main!] { fixture: "../fixture.roc", pf: platform "../../platform/main.roc" }
import fixture.LocalCases
main! = |_args| {
	{ bytes: LocalCases.snapshot(Bool.False).to_utf8(), work: [] }
}
