app [main!] { pf: platform "../../platform/main.roc", fixture: "../fixture.roc" }
import fixture.DateOracle
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| { bytes: DateOracle.run_args(args).to_utf8(), work: [1] }
