import cli.Cmd
import cli.Path
import FixtureOracles

Pending : { child : Cmd.Child, case : FixtureOracles.Case, label : Str }

## Four-way bounded native fixture replay. Compare in source order; close
## finished handles explicitly and retain raw bytes before interpreting them.
FixtureBatch := [].{
	replay! : { binary : Path, cases : List(FixtureOracles.Case), work : Path, prefix : Str } => Try({}, _)
	replay! = |{ binary, cases, work, prefix }| {
		if cases.is_empty() or cases.len() > 4096 {
			return Err(FixtureCases)
		}
		indexed = cases.map_with_index(|case, index| (case, "${prefix}-${index.to_str()}"))
		var $remaining = indexed.drop_first(4)
		var $pending = indexed.take_first(4).map_try!(
			|(case, label)| start!({
				binary,
				case,
				label,
			}),
		)?
		for _ in (0.U64).until(cases.len()) {
			first = $pending.first()?
			$pending = $pending.drop_first(1)
			outcome = first.child.wait!()
			first.child.close!().map_err(|error| FixtureCleanup(error))?
			(stdout_bytes, stderr_bytes) = match outcome {
				Ok(output) => (output.stdout_bytes, output.stderr_bytes)
				Err(Timeout(partial)) => (partial.stdout_bytes, partial.stderr_bytes)
				Err(OutputLimit(partial)) => (partial.stdout_bytes, partial.stderr_bytes)
				Err(_) => ([], [])
			}
			Path.write_bytes!(Path.join(work, "${first.label}.stdout"), stdout_bytes)?
			Path.write_bytes!(Path.join(work, "${first.label}.stderr"), stderr_bytes)?
			valid = match outcome {
				Ok(output) if output.status == Exited(0) => match (Str.from_utf8(stdout_bytes), Str.from_utf8(stderr_bytes)) {
					(Ok(stdout), Ok(_)) => FixtureOracles.is_matching_output(first.case.expected, stdout)
					_ => Bool.False
				}
				_ => Bool.False
			}
			if !valid {
				for pending in $pending {
					pending.child.close!().map_err(|error| FixtureCleanup(error))?
				}
				Path.write_utf8!(
					Path.join(work, "${first.label}.failure.json"),
					Json.to_str({
						case: first.case,
						stdout: Str.from_utf8_lossy(stdout_bytes),
						stderr: Str.from_utf8_lossy(stderr_bytes),
					}),
				)?
				return Err(FixtureMismatch(first.label, first.case.label))
			}
			match $remaining {
				[(case, label), .. as rest] => {
					$remaining = rest
					$pending = $pending.append(
						start!({
							binary,
							case,
							label,
						})?,
					)
				}
				[] => {}
			}
		}
		Ok({})
	}
}

start! : { binary : Path, case : FixtureOracles.Case, label : Str } => Try(Pending, _)
start! = |{ binary, case, label }| {
	child = Cmd.new(Path.to_os_str(binary)).args_str(case.input).timeout_ms(180000).manage_tree(Bool.True).output_limit(1048576).stdout(Capture).stderr(Capture).spawn!().map_err(|error| FixtureSpawn(error))?
	Ok({ child, case, label })
}
