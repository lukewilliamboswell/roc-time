platform ""
	requires {
		main! : U64 => I64
	}
	exposes [Host]
	packages {}
	provides { "roc_main": main_for_host! }
	hosted { "fixture_identity": Host.identity! }
	targets: {
		inputs_dir: "targets/",
		wasm32: {
			inputs: ["host.wasm", app],
			exports: ["probe", "allocation_attempts"],
		},
	}

import Host

main_for_host! : U64 => I64
main_for_host! = |input| main!(Host.identity!(input))
