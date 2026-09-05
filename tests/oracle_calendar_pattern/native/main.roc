app [main!] { pf: platform "../../platform/main.roc", fixture: "../fixture.roc" }
import fixture.PatternOracle
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| { bytes: PatternOracle.run_args(args).to_utf8(), work: [1] }
