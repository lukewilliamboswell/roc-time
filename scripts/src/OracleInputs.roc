import cli.OsStr
import cli.Path
import OracleOptions
import OracleManifest
import OracleStages
import Script

## Development-only reference inputs. Generators never see roc-time outputs;
## their products must match reviewed digests before a comparison can use them.
OracleInputs := [].{
	Request := {
		name : Str,
		manifest : OracleManifest.Manifest,
		cache : Path,
		source_mode : OracleOptions.SourceMode ?? CachedOnly,
	}
	Inputs : { corpus : Path, smoke : Path, gaps : [NoReferenceGaps, ReferenceGaps(Path)] }
	prepare! : Request => Try(Inputs, _)
	prepare! = |{ name, manifest, cache, source_mode }| {
		recipe = select_recipe(name)?
		require_hash!(Path.utf8(recipe.script), manifest.generator_adapter_sha256)?
		pins_path = Path.utf8("tests/oracles/dependencies.json")
		pins : Dependencies
		pins = Json.parse(Path.read_utf8!(pins_path)?)?
		python = match Script.env_str!("PYTHON") {
			Ok(program) => program
			Err(NotSet) => "python3"
			Err(error) => return Err(error)
		}
		version = Script.command(OsStr.from_str(python)).output!(["--version"])?
		if version != "Python ${pins.python}" {
			return Err(ReferencePythonVersion(version))
		}
		inputs_root = Path.join(cache, "${manifest.generator_adapter_sha256}/${hash_file!(pins_path)?}")
		corpus = Path.join(inputs_root, "tests/oracles/${name}.jsonl")
		smoke = Path.join(inputs_root, "tests/oracle_${name}/${if (name == "zones") "Cases.roc" else "SmokeCases.roc"}")
		gaps = Path.join(inputs_root, "tests/oracles/calendar_pattern-reference-gaps.jsonl")
		if !Path.exists!(corpus)? or !Path.exists!(smoke)? or (name == "calendar_pattern" and !Path.exists!(gaps)?) {
			wheels = Path.join(cache, "wheels")
			Path.create_all!(wheels)?
			required = match recipe.sources {
				NoWheels => []
				Dateutil => [dateutil_wheel, six_wheel]
				Zoneinfo => [tzdata_wheel]
			}
			for filename in required {
				pin = match pins.wheels.keep_if(|wheel| wheel.filename == filename) {
					[one] => one
					_ => return Err(ReferenceSourcePins(filename))
				}
				path = Path.join(wheels, filename)
				if !Path.exists!(path)? {
					match source_mode {
						CachedOnly => return Err(ReferenceToolMissing(Path.display(path)))
						FetchMissing => {
							pending = Path.join(wheels, "${filename}.download")
							_ = OracleStages.run!({
								command: [
									"curl",
									"--fail",
									"--location",
									"--retry",
									"2",
									"--max-time",
									"60",
									"--max-filesize",
									"16777216",
									pin.url,
									"--output",
									Path.display(pending),
								],
								cwd: Path.absolute!(".")?,
								logs: wheels,
								label: filename,
								timeout_ms: 90000,
							})?
							require_hash!(pending, pin.sha256)?
							Path.rename!(pending, path)?
						}
					}
				}
				require_hash!(path, pin.sha256)?
			}
			arguments = match recipe.sources {
				NoWheels => ["--refresh"]
				Dateutil => [Path.display(wheels)]
				Zoneinfo => [Path.display(Path.join(wheels, tzdata_wheel))]
			}
			Path.create_all!(inputs_root)?
			Script.info!({ label: "REFERENCE", message: "${name}: generating independent inputs in ${Path.display(inputs_root)}" })?
			_ = OracleStages.run!({
				command: [python, recipe.script].concat(arguments).concat(["--output-root", Path.display(inputs_root)]),
				cwd: Path.absolute!(".")?,
				logs: inputs_root,
				label: "generate",
				timeout_ms: 180000,
			})?
		}
		require_hash!(corpus, manifest.corpus_sha256)?
		require_hash!(smoke, manifest.smoke_sha256)?
		if name == "calendar_pattern" {
			require_hash!(gaps, manifest.gap_sha256)?
		}
		Ok({ corpus, smoke, gaps: if (name == "calendar_pattern") ReferenceGaps(gaps) else NoReferenceGaps })
	}
}

Dependencies : {
	python : Str,
	wheels : List(Wheel),
}

Wheel : {
	filename : Str,
	url : Str,
	sha256 : Str,
}

Recipe : { script : Str, sources : [NoWheels, Dateutil, Zoneinfo] }

select_recipe : Str -> Try(Recipe, [UnknownOracle])
select_recipe = |name| match name {
	"gregorian" | "julian" => Ok({ script: "scripts/oracles.py", sources: NoWheels })
	"zones" => Ok({ script: "scripts/generate_zone_oracle.py", sources: Zoneinfo })
	"calendar_pattern" => Ok({ script: "scripts/generate_pattern_oracle.py", sources: Dateutil })
	"rfc_date" => Ok({ script: "scripts/generate_rfc_date_oracle.py", sources: Dateutil })
	"rfc_timed" => Ok({ script: "scripts/generate_rfc_timed_oracle.py", sources: Dateutil })
	_ => Err(UnknownOracle)
}

dateutil_wheel = "python_dateutil-2.9.0.post0-py2.py3-none-any.whl"

six_wheel = "six-1.17.0-py2.py3-none-any.whl"

tzdata_wheel = "tzdata-2025.2-py2.py3-none-any.whl"

hash_file! : Path => Try(Str, _)
hash_file! = |path| Script.command("sha256sum").output!([Path.to_os_str(path)])?.split_on(" ").first()

require_hash! : Path, Str => Try({}, _)
require_hash! = |path, expected| {
	if hash_file!(path)? != expected {
		return Err(ReferenceIntegrity(Path.display(path)))
	}
	Ok({})
}

## Calendar profiles share one reference producer and cache identity.
expect select_recipe("gregorian")? == select_recipe("julian")?

## Unknown profiles cannot fall back to an unrelated generator.
expect select_recipe("unknown") == Err(UnknownOracle)
