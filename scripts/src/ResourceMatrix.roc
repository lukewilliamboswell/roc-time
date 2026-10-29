## Authored resource scenarios and independent transport/budget expectations.
## These preserve the domains and laws of the native fixture probes; they do
## not derive expected output from the temporal package.
ResourceMatrix := [].{
	Check : { args : List(Str), stdout : [Exact(Str), Ignore], length : U64, zeros : List(U64), positive : List(U64), values : List((U64, U64)), ceilings : List((U64, U64)), equal_group : Str, reference_group : Str, growth : List(U64), prefix : List(Str) }
	Failure : { args : List(Str), mode : Str, must_fail : Bool, diagnostic : Str, before : Str, after : Str }
	Fixture : { name : Str, source : Str, unit_test : Bool, debug : Bool, checks : List(Check), failures : List(Failure) }

	all : List(Fixture)
	all = {
		var $fixtures = []
		var $checks = []
		for (first, second, comparison) in [("42", "43", 0.U64), ("43", "42", 2), ("42", "42", 1), ("-9223372036854775808", "9223372036854775807", 0)] {
			$checks = $checks.append({ ..sample([first, second], Exact(first.repeat(64)), 3), zeros: [0], positive: [2], values: [(1, comparison)], prefix: ["ROC_TRACE protocol=1 mark=1 allocations=1", "ROC_TRACE protocol=1 mark=2 allocations=1"] })
		}
		$fixtures = $fixtures.append({ name: "probe", source: "tests/platform_probe/main.roc", unit_test: Bool.True, debug: Bool.True, checks: $checks, failures: [failure(["fail-assert"]), { ..failure(["fail-expect"]), mode: "dev", diagnostic: "[ROC EXPECT]" }, { ..failure(["fail-expect"]), mode: "speed", must_fail: Bool.False }] })
		$checks = []
		for year in ["2001", "2000000000"] {
			$checks = $checks.append({ ..sample([year, "4096"], Exact("prefix=1,resume=2,limited=1,zero=1\n"), 30), equal_group: "horizon" })
		}
		$fixtures = $fixtures.append({ ..fixture("recurrence", $checks, [failure(["2000000000", "0"])]), unit_test: Bool.True })
		$checks = []
		var $failures = []
		for ownership in ["owned", "shared", "sliced"] {
			for size in [64.U64, 512, 4096] {
				$checks = $checks.append({ ..sample([size.to_str(), (1024 * size + 8192).to_str(), ownership], Exact("independent=definite,edge=possible,outside=impossible,paired-gap=impossible\n"), 4), zeros: [1, 3], reference_group: ownership, growth: if (size == 4096) [0, 2] else [] })
			}
			$failures = $failures.append(failure(["4096", "0", ownership]))
		}
		$fixtures = $fixtures.append(fixture("interval", $checks, $failures))
		$checks = []
		exact = "1970-01-01T01:00:00+01:00/1970-01-01T00:00:02Z"
		edtf = "?2004-%06~-~11?"
		for tags in ["1", "32"] {
			for transitions in ["2", "16384"] {
				$checks = $checks.append({ ..sample([transitions, tags, "4194304", exact, edtf, "16384"], Exact("instant=1000000,presentation=1000000,exact=0..2000000,edtf=scopes-preserved\n"), 26), zeros: [3, 10, 17, 18, 19], equal_group: tags })
			}
		}
		$failures = [failure(["16384", "32", "0"]), { ..failure(["2", "1", "4194304", exact, edtf, "0"]), before: "mark=3 ", after: "mark=4 " }]
		for (date, clock, english) in [("0000-01-01", "00:00:00", "1 Jan 0000"), ("2026-09-07", "09:30:00.0012", "7 Sep 2026"), ("+2147483647-12-31", "23:59:59.999999", "31 Dec +2147483647")] {
			base = ["2", "1", "4194304", exact, edtf, "16384", date, clock, "${date}T${clock}", "4096"]
			$checks = $checks.append({ ..sample(base.concat(["0", english]), Ignore, 26), zeros: [17, 18, 19], ceilings: [11.U64, 12, 13, 14, 15, 16, 20, 21, 22, 23, 24, 25].map(|index| (index, 4096)) })
			if date == "+2147483647-12-31" {
				for scope in (1.U64).to(9) {
					marker = scope + (if (scope <= 6) 4 else 5)
					$failures = $failures.append({ ..failure(base.concat([scope.to_str(), english])), before: "mark=${marker.to_str()} ", after: "mark=${(marker + 1).to_str()} " })
				}
			}
		}
		$fixtures = $fixtures.append(fixture("interchange", $checks, $failures))
		$checks = []
		for text in ["4", "524288"] {
			for transitions in ["2", "16384"] {
				$checks = $checks.append({ ..sample([transitions, text, "65536"], Exact("render=bounded,instant=known,presentation=unsupported\n"), 7), zeros: [0, 1, 2, 6], equal_group: text })
			}
		}
		$fixtures = $fixtures.append(fixture("explanation", $checks, [failure(["16384", "524288", "0"])]))
		$checks = []
		for kind in (0.U64).to(4) {
			for days in ["1", "9223372036854775807"] {
				for form in ["utc", "local"] {
					$checks = $checks.append({ ..sample([kind.to_str(), days, form, "65536"], Exact("facts=preserved,render=bounded,end=not-invented\n"), 5), zeros: [0, 1] })
				}
			}
		}
		$fixtures = $fixtures.append(fixture("declaration_explanation", $checks, [failure(["4", "9223372036854775807", "local", "0"])]))
		$checks = []
		for count in ["2", "16384"] {
			for text in ["4", "524288"] {
				for kind in ["coverage", "boundary", "selection", "batch"] {
					for ownership in ["owned", "shared", "sliced"] {
						$checks = $checks.append({ ..sample([count, text, kind, ownership, "65536"], Exact("selection=facts-bounded,incompleteness-preserved\n"), 6), zeros: [0, 1, 2] })
					}
				}
			}
		}
		$fixtures = $fixtures.append(fixture("selection_explanation", $checks, [failure(["2", "4", "batch", "shared", "0"])]))
		$checks = []
		for count in ["2", "4096"] {
			for termination in ["forever", "count"] {
				for kind in ["date", "timed", "rfc"] {
					$checks = $checks.append({ ..sample([count, termination, kind, "65536"], Exact("recurrence=declaration,budget=bounded\n"), 6), zeros: [0, 1, 2] })
				}
			}
		}
		$fixtures = $fixtures.append(fixture("recurrence_explanation", $checks, [failure(["2", "forever", "date", "0"])]))
		$checks = []
		for count in [1.U64, 32, 32000] {
			for year in ["0000", "9999"] {
				for ownership in ["owned", "shared"] {
					$checks = $checks.append({ ..sample([count.to_str(), year, ownership, "1"], Exact("format=canonical,width=preserved,assertion=preserved\n"), 3), ceilings: [(0, count), (1, count * 128)] })
				}
			}
		}
		$fixtures = $fixtures.append(fixture("timestamp_format", $checks, [failure(["32", "0000", "shared", "0"])]))
		$checks = []
		for ownership in ["owned", "shared", "sliced"] {
			for count in ["1", "32", "32000"] {
				$checks = $checks.append({ ..sample([count, ownership], Exact("queries=exact\n"), 5), zeros: [2, 3], positive: [4] })
			}
		}
		$fixtures = $fixtures.append(fixture("civil_query", $checks, [failure(["32", "shared", "control"])]))
		for kind in ["date_export", "timed_export", "schedule_definition", "boundary_exclusions"] {
			$checks = []
			for ownership in ["owned", "shared", "sliced"] {
				for count in [0.U64, 1, 64, 4096] {
					for horizon in if (kind == "date_export") ["2001", "2000000000"] else ["2001", "200000"] {
						ceiling = if (kind == "boundary_exclusions") 16384 else 65536 + count * (if (kind == "schedule_definition") 1024 else 256)
						months = if (count == 0) "" else if (count == 1) ";BYMONTH=1" else ";BYMONTH=1,2,3,4,5,6,7,8,9,10,11,12"
						text = if (kind == "date_export") "FREQ=DAILY;INTERVAL=1${months};WKST=MO" else if (kind == "timed_export") "FREQ=DAILY;INTERVAL=1${months};BYHOUR=0;BYMINUTE=0;BYSECOND=0;WKST=MO" else if (kind == "schedule_definition") "schedule-definition" else "boundary-exclusions"
						length = if (kind == "date_export") 7 else if (kind == "timed_export") 8 else 6
						ceilings = if (kind == "date_export") [(3.U64, ceiling), (4, 4096), (5, 4096), (6, 4096)] else if (kind == "timed_export") [(3, ceiling), (4, ceiling), (5, 16384), (6, 16384), (7, 16384)] else [(1, if (kind == "boundary_exclusions") 65536 + count * 64 else ceiling), (3, 16384), (4, 16384), (5, 16384)]
						$checks = $checks.append({ ..sample([count.to_str(), ownership, horizon, ceiling.to_str()], Exact(text), length), zeros: [2], ceilings, equal_group: "${ownership}/${count.to_str()}" })
					}
				}
			}
			count = if (kind == "boundary_exclusions") "4096" else "64"
			horizon = if (kind == "date_export") "2000000000" else "200000"
			$fixtures = $fixtures.append(fixture(kind, $checks, [failure([count, "shared", horizon, "0"])]))
		}
		$fixtures
	}
}

sample = |args, stdout, length| { args, stdout, length, zeros: [], positive: [], values: [], ceilings: [], equal_group: "", reference_group: "", growth: [], prefix: [] }

failure = |args| { args, mode: "", must_fail: Bool.True, diagnostic: "ROC_ASSERT_FAILED", before: "", after: "" }

fixture = |name, checks, failures| { name, source: "tests/${name}_resource/main.roc", checks, failures, unit_test: Bool.False, debug: Bool.False }
