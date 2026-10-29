## Admission of roc-fuzz 0.5 quality evidence. A successful process alone is
## insufficient: named examples need complete metrics and exploration must
## actually accept input. Baselines are accepted only by an explicit operation.
FuzzEvidence := [].{
	Example : {
		name : Str,
		revision : Str,
		input_sha256 : Str,
		outcome : Str,
		metric_valid : Bool,
		trace_rules_passed : Bool,
		capture_complete : Bool,
	}
	Report : {
		format : Str,
		metric_version : Str,
		target : Str,
		host_target : Str,
		outcome : Str,
		baseline_status : Str,
		examples : List(Example),
		exploration : { status : Str, attempted : U64, accepted : U64, rejected : U64 },
	}
	Baseline : [Accepted, Matched, NotChecked]
	Exploration : [RequireAcceptedInput, NotRequested]
	validate : Report, { host : Str, baseline : Baseline, exploration : Exploration } -> Try({}, [FuzzEvidence])
	validate = |report, { host, baseline, exploration }| {
		expected_baseline = match baseline {
			Accepted => "accepted"
			Matched => "matched"
			NotChecked => "not_checked"
		}
		identity = {
			format: report.format,
			metric_version: report.metric_version,
			host: report.host_target,
			outcome: report.outcome,
			baseline: report.baseline_status,
		}
		expected_identity = {
			format: "roc-fuzz-quality/1",
			metric_version: "roc-fuzz-allocations/1",
			host,
			outcome: "passed",
			baseline: expected_baseline,
		}
		if identity != expected_identity or report.examples.is_empty() {
			return Err(FuzzEvidence)
		}
		if report.examples.any(
			|example| {
				has_identity = !example.name.is_empty() and !example.revision.is_empty()
				has_digest = example.input_sha256.count_utf8_bytes() == 64
				has_complete_metrics = example.metric_valid and example.trace_rules_passed and example.capture_complete
				example.outcome != "passed" or !has_identity or !has_digest or !has_complete_metrics
			},
		) {
			return Err(FuzzEvidence)
		}
		if exploration == RequireAcceptedInput {
			counts = report.exploration
			if counts.status != "passed" or counts.accepted == 0 or counts.accepted > counts.attempted {
				return Err(FuzzEvidence)
			}
			if counts.rejected > counts.attempted - counts.accepted {
				return Err(FuzzEvidence)
			}
		}
		Ok({})
	}
}

fixture = {
	format: "roc-fuzz-quality/1",
	metric_version: "roc-fuzz-allocations/1",
	target: "clock-v1",
	host_target: "x64musl",
	outcome: "passed",
	baseline_status: "matched",
	examples: [
		{
			name: "zero",
			revision: "1",
			input_sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			outcome: "passed",
			metric_valid: Bool.True,
			trace_rules_passed: Bool.True,
			capture_complete: Bool.True,
		},
	],
	exploration: { status: "passed", attempted: 2, accepted: 1, rejected: 1 },
}

## Accept complete matched examples and observed exploration.
expect FuzzEvidence.validate(
	fixture,
	{
		host: "x64musl",
		baseline: Matched,
		exploration: RequireAcceptedInput,
	},
) == Ok({})

## Reject a missing allocation baseline.
expect FuzzEvidence.validate(
	{ ..fixture, baseline_status: "unbaselined" },
	{
		host: "x64musl",
		baseline: Matched,
		exploration: RequireAcceptedInput,
	},
) == Err(FuzzEvidence)

## Reject exploration that accepted no inputs.
expect FuzzEvidence.validate(
	{ ..fixture, exploration: { status: "passed", attempted: 2, accepted: 0, rejected: 2 } },
	{
		host: "x64musl",
		baseline: Matched,
		exploration: RequireAcceptedInput,
	},
) == Err(FuzzEvidence)

## Require a nonempty named-example inventory.
expect FuzzEvidence.validate(
	{ ..fixture, examples: [] },
	{
		host: "x64musl",
		baseline: Matched,
		exploration: RequireAcceptedInput,
	},
) == Err(FuzzEvidence)

## Reject incomplete allocation metrics.
expect FuzzEvidence.validate(
	{ ..fixture, examples: fixture.examples.map(|example| { ..example, metric_valid: Bool.False }) },
	{
		host: "x64musl",
		baseline: Matched,
		exploration: RequireAcceptedInput,
	},
) == Err(FuzzEvidence)

## Reject accepted-input counts above attempted executions.
expect FuzzEvidence.validate(
	{ ..fixture, exploration: { status: "passed", attempted: 1, accepted: 2, rejected: 0 } },
	{
		host: "x64musl",
		baseline: Matched,
		exploration: RequireAcceptedInput,
	},
) == Err(FuzzEvidence)
