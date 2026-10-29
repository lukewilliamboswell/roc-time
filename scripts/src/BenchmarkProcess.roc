import cli.Cmd
import cli.Path

## Supervise build/measurement processes without shell or Python launchers.
## Timings belong to the subjects' in-process records, not this wrapper.
BenchmarkProcess := [].{
	run! : List(Str), Path, Path, Str, List((Str, Str)), U64 => Try({ stdout : Str, stderr : Str }, _)
	run! = |args, cwd, logs, label, environment, timeout| {
		var $command = Cmd.new_str(args.first()?).args_str(args.drop_first(1)).cwd(cwd).timeout_ms(timeout).manage_tree(Bool.True).output_limit(16777216).stdout(Capture).stderr(Capture)
		for (key, value) in environment {
			$command = $command.env_str(key, value)
		}
		outcome = $command.run!()
		(stdout, stderr) = match outcome {
			Ok(output) => (output.stdout_bytes, output.stderr_bytes)
			Err(Timeout(partial)) => (partial.stdout_bytes, partial.stderr_bytes)
			Err(OutputLimit(partial)) => (partial.stdout_bytes, partial.stderr_bytes)
			Err(_) => ([], [])
		}
		Path.write_bytes!(Path.join(logs, "${label}.stdout"), stdout)?
		Path.write_bytes!(Path.join(logs, "${label}.stderr"), stderr)?
		match outcome {
			Ok({ status: Exited(0), .. }) => Ok({ stdout: Str.from_utf8(stdout)?, stderr: Str.from_utf8(stderr)? })
			Ok(output) => Err(BenchmarkStatus(label, output.status))
			Err(error) => Err(BenchmarkSupervision(label, Str.inspect(error)))
		}
	}
}
