app [main!] { pf: platform "../../platform/main.roc", fixture: "../fixture.roc" }
import fixture.TimedOracle
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| { bytes: TimedOracle.run_args(args).to_utf8(), work: [1] }
