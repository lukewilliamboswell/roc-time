platform ""
	requires {
		main! : List(Str) => { bytes : List(U8), work : List(U64) }
	}
	exposes [Host]
	packages {}
	provides { "roc_main": main_for_host! }
	hosted {
		"fixture_allocation_count": Host.allocation_count!,
		"fixture_allocated_bytes": Host.allocated_bytes!,
		"fixture_deallocation_count": Host.deallocation_count!,
		"fixture_mark": Host.mark!,
		"fixture_assert": Host.assert!,
	}
	targets: {
		inputs_dir: "../../.roc-time-tmp/fixture-platform/targets/",
		arm64mac: { inputs: ["libhost.a", app] },
		x64musl: { inputs: ["crt1.o", "libhost.a", app, "libc.a"] },
	}
import Host
main_for_host! : List(Str) => { bytes : List(U8), work : List(U64) }
main_for_host! = |args| main!(args)
