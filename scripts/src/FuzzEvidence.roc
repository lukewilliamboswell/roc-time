## Admission of roc-fuzz 0.5 quality evidence. A successful process alone is
## insufficient: named examples need complete metrics and exploration must
## actually accept input. Baselines are accepted only by an explicit operation.
FuzzEvidence := [].{
	Example : { name : Str, revision : Str, input_sha256 : Str, outcome : Str, metric_valid : Bool, trace_rules_passed : Bool, capture_complete : Bool }
	Report : { format : Str, metric_version : Str, target : Str, host_target : Str, outcome : Str, baseline_status : Str, examples : List(Example), exploration : { status : Str, attempted : U64, accepted : U64, rejected : U64 } }
	validate : Report, Str, Str, Bool -> Try({}, [FuzzEvidence])
	validate = |report, host, baseline, search| {
		if report.format != "roc-fuzz-quality/1" or report.metric_version != "roc-fuzz-allocations/1" or report.host_target != host or report.outcome != "passed" or report.baseline_status != baseline or report.examples.is_empty() {
			return Err(FuzzEvidence)
		}
		if report.examples.any(|example| example.name.is_empty() or example.revision.is_empty() or example.input_sha256.count_utf8_bytes() != 64 or example.outcome != "passed" or !example.metric_valid or !example.trace_rules_passed or !example.capture_complete) {
			return Err(FuzzEvidence)
		}
		if search and (report.exploration.status != "passed" or report.exploration.accepted == 0 or report.exploration.accepted > report.exploration.attempted or report.exploration.rejected > report.exploration.attempted - report.exploration.accepted) {
			return Err(FuzzEvidence)
		}
		Ok({})
	}
}

fixture = { format: "roc-fuzz-quality/1", metric_version: "roc-fuzz-allocations/1", target: "clock-v1", host_target: "x64musl", outcome: "passed", baseline_status: "matched", examples: [{ name: "zero", revision: "1", input_sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", outcome: "passed", metric_valid: Bool.True, trace_rules_passed: Bool.True, capture_complete: Bool.True }], exploration: { status: "passed", attempted: 2, accepted: 1, rejected: 1 } }
expect FuzzEvidence.validate(fixture, "x64musl", "matched", Bool.True) == Ok({})
expect FuzzEvidence.validate({ ..fixture, baseline_status: "unbaselined" }, "x64musl", "matched", Bool.True) == Err(FuzzEvidence)
expect FuzzEvidence.validate({ ..fixture, exploration: { status: "passed", attempted: 2, accepted: 0, rejected: 2 } }, "x64musl", "matched", Bool.True) == Err(FuzzEvidence)
expect FuzzEvidence.validate({ ..fixture, examples: [] }, "x64musl", "matched", Bool.True) == Err(FuzzEvidence)
expect FuzzEvidence.validate({ ..fixture, examples: fixture.examples.map(|example| { ..example, metric_valid: Bool.False }) }, "x64musl", "matched", Bool.True) == Err(FuzzEvidence)
expect FuzzEvidence.validate({ ..fixture, exploration: { status: "passed", attempted: 1, accepted: 2, rejected: 0 } }, "x64musl", "matched", Bool.True) == Err(FuzzEvidence)
