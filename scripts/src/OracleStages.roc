import cli.Cmd
import cli.Monotonic
import cli.Path

## Every compiler/interpreter stage has a process-group deadline and combined
## capture limit. Logs survive nonzero exits, signals and budget failures.
OracleStages := [].{
	run! : List(Str), Path, Str => Try({ stdout : Str, stderr : Str, seconds : F64 }, _)
	run! = |command, cwd, label| {
		before = Monotonic.now!()
		outcome = Cmd.new_str(command.first()?).args_str(command.drop_first(1)).cwd(cwd).timeout_ms(120000).manage_tree(Bool.True).output_limit(1048576).stdout(Capture).stderr(Capture).run!()
		seconds = (Monotonic.now!() - before).to_f64() / 1000000000
		(stdout, stderr) = match outcome {
			Ok(output) => (output.stdout_bytes, output.stderr_bytes)
			Err(Timeout(partial)) => (partial.stdout_bytes, partial.stderr_bytes)
			Err(OutputLimit(partial)) => (partial.stdout_bytes, partial.stderr_bytes)
			Err(_) => ([], [])
		}
		Path.write_bytes!(Path.join(cwd, "${label}.stdout"), stdout)?
		Path.write_bytes!(Path.join(cwd, "${label}.stderr"), stderr)?
		match outcome {
			Ok(output) if output.status == Exited(0) => Ok({ stdout: Str.from_utf8(stdout)?, stderr: Str.from_utf8(stderr)?, seconds })
			Ok(output) => Err(StageStatus(label, output.status))
			Err(error) => Err(StageSupervision(label, Str.inspect(error)))
		}
	}
}
