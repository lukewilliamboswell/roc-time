import cli.Cmd
import cli.Monotonic
import cli.Path

## Every compiler/interpreter stage has a process-group deadline and combined
## capture limit. Logs survive nonzero exits, signals and budget failures.
OracleStages := [].{
	run! : List(Str), Path, Str => Try({ stdout : Str, stderr : Str, seconds : F64 }, _)
	run! = |command, cwd, label| run_with_deadline!(command, cwd, label, 120000)

	run_with_deadline! : List(Str), Path, Str, U64 => Try({ stdout : Str, stderr : Str, seconds : F64 }, _)
	run_with_deadline! = |command, cwd, label, timeout| run_logged!(command, cwd, cwd, label, timeout)

	run_logged! : List(Str), Path, Path, Str, U64 => Try({ stdout : Str, stderr : Str, seconds : F64 }, _)
	run_logged! = |command, cwd, logs, label, timeout| {
		before = Monotonic.now!()
		outcome : Try(Cmd.RunOutput, Cmd.RunErr)
		outcome = Cmd.new_str(command.first()?).args_str(command.drop_first(1)).cwd(cwd).timeout_ms(timeout).manage_tree(Bool.True).output_limit(1048576).stdout(Capture).stderr(Capture).run!()
		seconds = (Monotonic.now!() - before).to_f64() / 1000000000
		(stdout, stderr) = match outcome {
			Ok(output) => (output.stdout_bytes, output.stderr_bytes)
			Err(Timeout(partial)) => (partial.stdout_bytes, partial.stderr_bytes)
			Err(OutputLimit(partial)) => (partial.stdout_bytes, partial.stderr_bytes)
			Err(_) => ([], [])
		}
		Path.write_bytes!(Path.join(logs, "${label}.stdout"), stdout)?
		Path.write_bytes!(Path.join(logs, "${label}.stderr"), stderr)?
		match outcome {
			Ok({ status: Exited(0), .. }) => Ok({ stdout: Str.from_utf8(stdout)?, stderr: Str.from_utf8(stderr)?, seconds })
			Ok(output) => Err(StageStatus(label, output.status))
			Err(error) => Err(StageSupervision(label, Str.inspect(error)))
		}
	}
}
