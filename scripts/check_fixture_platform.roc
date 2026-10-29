#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import src/FixtureHost
import src/ResourceMatrix
import src/ResourceMetrics
import src/Script

main! = |_args| {
	target = FixtureHost.build!()?
	nightly = Script.roc_nightly!()?
	version = nightly.output!(["version"])?
	work = Env.create_temp_dir_in!(Path.absolute!(".roc-time-tmp")?, "fixture-verification-")?
	for fixture in ResourceMatrix.all {
		nightly.cmd(["check", OsStr.from_str(fixture.source)]).timeout_ms(120000).exec_cmd!()?
		if fixture.unit_test {
			nightly.cmd(["test", OsStr.from_str(fixture.source)]).timeout_ms(120000).exec_cmd!()?
		}
		for mode in ["dev", "speed"] {
			binary = Path.join(work, "${fixture.name}-${mode}")
			args = ["build", fixture.source, "--opt=${mode}", "--target=${target}", "--output=${Path.display(binary)}", "--no-cache"]
			build_args = if fixture.debug {
				args.append("--debug")
			} else {
				args
			}
			nightly.cmd(build_args.map(OsStr.from_str)).timeout_ms(120000).exec_cmd!()?
			var $observations = []
			var $equal = Dict.empty()
			var $references = Dict.empty()
			for check in fixture.checks {
				result = Cmd.new(Path.to_os_str(binary)).args_str(check.args).timeout_ms(if (fixture.name == "probe") 10000 else 5000).stdout(Capture).stderr(Capture).run!()?
				stdout = Str.from_utf8(result.stdout_bytes)?
				stderr = Str.from_utf8(result.stderr_bytes)?
				if result.status != Exited(0) {
					return Script.fail!("${fixture.name}/${mode}: ${Str.inspect(check.args)} failed:\n${stderr}")
				}
				match check.stdout {
					Exact(expected) if stdout != expected => return Script.fail!("${fixture.name}/${mode}: changed semantic output ${stdout}")
					_ => {}
				}
				metrics = ResourceMetrics.read(stderr, check.length)?
				$observations = $observations.append({ args: check.args, metrics, stdout, stderr })
				for index in check.zeros {
					if metrics.get(index)? != 0 {
						return Err(UnexpectedAllocation(fixture.name, index))
					}
				}
				for index in check.positive {
					if metrics.get(index)? == 0 {
						return Err(MissingObservation(fixture.name, index))
					}
				}
				for (index, expected) in check.values {
					if metrics.get(index)? != expected {
						return Err(ChangedObservation(fixture.name, index))
					}
				}
				for (index, ceiling) in check.ceilings {
					if metrics.get(index)? > ceiling {
						return Err(ResourceCeiling(fixture.name, index))
					}
				}
				if !check.prefix.is_empty() {
					lines = stderr.drop_suffix("\n").split_on("\n")
					if lines.len() != check.prefix.len() + 1 or lines.take_first(check.prefix.len()) != check.prefix {
						return Err(ChangedTrace)
					}
					line = lines.last()?
					parts = line.split_on(" ")
					if parts.len() != 6 or parts.get(0)? != "ROC_METRICS" or parts.get(1)? != "protocol=1" {
						return Err(MalformedMetrics)
					}
					for (index, prefix) in [(2.U64, "allocations="), (3, "requested_bytes="), (4, "deallocations=")] {
						part = parts.get(index)?
						if !part.starts_with(prefix) {
							return Err(MalformedMetrics)
						}
						_ = U64.from_str(part.drop_prefix(prefix))?
					}
				}
				if !check.equal_group.is_empty() {
					match $equal.get(check.equal_group) {
						Ok(prior) if prior != metrics => return Err(ExtentDependentTraffic(fixture.name, check.equal_group))
						_ => {}
					}
					$equal = $equal.insert(check.equal_group, metrics)
				}
				if !check.reference_group.is_empty() {
					match $references.get(check.reference_group) {
						Ok(prior) => for index in check.growth {
							if !ResourceMetrics.within_growth(prior.get(index)?, metrics.get(index)?) {
								return Err(NonlinearTraffic(fixture.name, index))
							}
						}
						Err(_) if check.growth.is_empty() => {
							$references = $references.insert(check.reference_group, metrics)
						}
						Err(_) => return Err(MissingGrowthReference)
					}
				}
			}
			Path.write_utf8!(Path.join(work, "${fixture.name}-${mode}.json"), Json.to_str({ compiler: version, target, mode, observations: $observations }))?
			for failure in fixture.failures {
				if failure.mode.is_empty() or failure.mode == mode {
					result = Cmd.new(Path.to_os_str(binary)).args_str(failure.args).timeout_ms(if (fixture.name == "probe") 10000 else 5000).stdout(Capture).stderr(Capture).run!()?
					_ = Str.from_utf8(result.stdout_bytes)?
					stderr = Str.from_utf8(result.stderr_bytes)?
					if failure.must_fail {
						match result.status {
							Exited(code) if code != 0 and stderr.contains(failure.diagnostic) => {}
							_ => return Script.fail!("${fixture.name}/${mode}: failure control ${Str.inspect(failure.args)} returned ${Str.inspect(result.status)}:\n${stderr}")
						}
						if !failure.before.is_empty() and !ResourceMetrics.failure_in_scope(stderr, failure.before, failure.after) {
							return Script.fail!("${fixture.name}/${mode}: misplaced failure ${Str.inspect(failure.args)}:\n${stderr}")
						}
					} else if result.status != Exited(0) {
						return Err(OptimizedExpectChanged)
					}
				}
			}
			Script.info!("PASS", "${fixture.name}/${mode}: ${fixture.checks.len().to_str()} resource scenarios, independent laws and failure controls")?
		}
	}
	Script.info!("EVIDENCE", Path.display(work))
}
