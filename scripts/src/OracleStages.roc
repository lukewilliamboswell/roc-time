import cli.Cmd
import cli.OsStr
import cli.Duration
import cli.Monotonic
import cli.Path

## Every compiler/interpreter stage has a process-group deadline and combined
## capture limit. Logs survive nonzero exits, signals and budget failures.
OracleStages := [].{
	Request := {
		command : List(Str),
		cwd : Path,
		logs : Path,
		label : Str,
		timeout_ms : U64 ?? 120000,
	}
	Output : { stdout : Str, stderr : Str, seconds : F64 }
	run! : Request => Try(Output, _)
	run! = |{ command, cwd, logs, label, timeout_ms }| {
		before = Monotonic.now!()
		outcome : Try(Cmd.Output, [CmdErr(Cmd.Err), Interrupted, Closed])
		outcome = Cmd.new(OsStr.from_str(command.first()?)).args((command.drop_first(1)).map(OsStr.from_str)).cwd(cwd).timeout(Duration.millis(timeout_ms)).manage_tree(Bool.True).output_limit(MaxBytes(1048576)).stdout(Capture).stderr(Capture).run!()
		seconds = before.elapsed!().to_nanos().to_f64() / 1000000000
		(stdout, stderr) = match outcome {
			Ok(output) => (output.stdout_bytes, output.stderr_bytes)
			Err(CmdErr(TimedOut(partial))) => (partial.stdout_bytes, partial.stderr_bytes)
			Err(CmdErr(OutputLimitExceeded(partial))) => (partial.stdout_bytes, partial.stderr_bytes)
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
