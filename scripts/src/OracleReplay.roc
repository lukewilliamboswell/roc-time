import cli.Cmd
import cli.Monotonic
import cli.Path
import NativeMetrics
import OracleCases

Pending : { child : Cmd.Child, case : OracleCases.Case, command : List(Str), start : U64 }

## Bounded FIFO supervision: at most `workers` live child handles, exact
## comparison in corpus order, and preserved bounded artifacts on failure.
## Timing runs from spawn through ordered collection, including queue wait.
## Completed handles are closed explicitly even if backing slices retain them.
OracleReplay := [].{
	FailureKind : [Timeout, OutputLimit, Status, InvalidUtf8, Mismatch, InvalidMetrics, Incomplete, Supervision]
	Result : { id : Str, observation : List(Str), observed_after_seconds : F64, allocations : U64, requested_bytes : U64, deallocations : U64, work : List(U64), traces : List(NativeMetrics.Trace) }
	replay! : Path, List(OracleCases.Case), Path, U64 => Try(List(Result), _)
	replay! = |binary, cases, session, workers| {
		if workers < 1 or workers > 16 or cases.is_empty() {
			return Err(OracleArguments)
		}
		var $remaining = cases.drop_first(workers)
		var $pending = cases.take_first(workers).map_try!(|case| start!(binary, case, session, 5000))?
		var $results = []
		for _ in (0.U64).until(cases.len()) {
			first = $pending.first()?
			$pending = $pending.drop_first(1)
			outcome = first.child.wait!()
			first.child.close!().map_err(|close_error| OracleCleanup(close_error))?
			match finish!(first, outcome, session) {
				Ok(result) => {
					$results = $results.append(result)
				}
				Err(error) => {
					for pending in $pending {
						pending.child.close!().map_err(|cleanup_error| OracleCleanup(cleanup_error))?
					}
					return Err(error)
				}
			}
			match $remaining {
				[case, .. as rest] => {
					$remaining = rest
					$pending = $pending.append(start!(binary, case, session, 5000)?)
				}
				[] => {}
			}
		}
		results = $results
		if results.map(|result| result.id) != cases.map(|case| case.id) {
			return Err(OracleIdentities)
		}
		Path.write_utf8!(Path.join(session, "results.jsonl"), "${Str.join_with(results.map_try(|result| Json.to_str_try(result))?, "\n")}\n")?
		Ok(results)
	}
	one! : Path, OracleCases.Case, Path, U64 => Try(Result, _)
	one! = |binary, case, session, timeout| {
		pending = start!(binary, case, session, timeout)?
		outcome = pending.child.wait!()
		pending.child.close!().map_err(|close_error| OracleCleanup(close_error))?
		finish!(pending, outcome, session)
	}
}

start! : Path, OracleCases.Case, Path, U64 => Try(Pending, _)
start! = |binary, case, session, timeout| {
	identity = U64.from_str(case.id).map_err(|_| OracleArguments)?
	if identity > 4095 or identity.to_str() != case.id {
		return Err(OracleArguments)
	}
	command = [Path.display(binary), case.id, case.operation].concat(case.input)
	start = Monotonic.now!()
	child = Cmd.new(Path.to_os_str(binary)).args_str(command.drop_first(1)).cwd(session).timeout_ms(timeout).manage_tree(Bool.True).output_limit(16384).stdout(Capture).stderr(Capture).spawn!().map_err(|error| OracleSpawn(error))?
	Ok({ child, case, command, start })
}

finish! : Pending, Try(Cmd.RunOutput, Cmd.RunErr), Path => Try(OracleReplay.Result, _)
finish! = |pending, outcome, session| {
	seconds = (Monotonic.now!() - pending.start).to_f64() / 1000000000
	(result, stdout_bytes, stderr_bytes) = match outcome {
		Ok(output) => (validate(pending.case, output, seconds), output.stdout_bytes, output.stderr_bytes)
		Err(Timeout(partial)) => (Err(Timeout), partial.stdout_bytes, partial.stderr_bytes)
		Err(OutputLimit(partial)) => (Err(OutputLimit), partial.stdout_bytes, partial.stderr_bytes)
		Err(_) => (Err(Supervision), [], [])
	}
	match result {
		Ok(observation) => Ok(observation)
		Err(kind) => {
			artifact = { case: pending.case, command: pending.command, kind, stdout: Str.from_utf8_lossy(stdout_bytes), stderr: Str.from_utf8_lossy(stderr_bytes) }
			Path.write_utf8!(Path.join(session, "failure-${pending.case.id}.json"), Json.to_str(artifact))?
			Err(OracleCaseFailure({ id: pending.case.id, kind }))
		}
	}
}

validate : OracleCases.Case, Cmd.RunOutput, F64 -> Try(OracleReplay.Result, OracleReplay.FailureKind)
validate = |case, output, seconds| {
	if output.status != Exited(0) {
		return Err(Status)
	}
	stdout = Str.from_utf8(output.stdout_bytes).map_err(|_| InvalidUtf8)?
	stderr = Str.from_utf8(output.stderr_bytes).map_err(|_| InvalidUtf8)?
	if !OracleCases.compare(case, stdout) {
		return Err(Mismatch)
	}
	metrics = NativeMetrics.parse(stderr).map_err(|_| InvalidMetrics)?
	if metrics.work != [1] {
		return Err(Incomplete)
	}
	Ok({ id: case.id, observation: stdout.drop_suffix("\n").split_on("\t").drop_first(1), observed_after_seconds: seconds, allocations: metrics.allocations, requested_bytes: metrics.requested_bytes, deallocations: metrics.deallocations, work: metrics.work, traces: metrics.traces })
}
