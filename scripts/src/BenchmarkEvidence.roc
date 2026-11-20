import cli.Path
import BenchmarkTimingCache
import ComparisonOptions
import Script

## Capture and validate reproducible native benchmark identities and evidence.
BenchmarkEvidence := [].{
	host! : () => Try(Dict(Str, Str), _)
	host! = || {
		host = Script.command("uname").output!(["-s"])?
		arch = Script.command("uname").output!(["-m"])?
		system_release = Script.command("uname").output!(["-sr"])?
		hardware = if host == "Darwin" {
			Script.command("system_profiler").output!(["SPHardwareDataType"])?.split_on("\n").map(Str.trim).keep_if(
				|line| {
					["Chip:", "Model Identifier:", "Total Number of Cores:"].any(|prefix| line.starts_with(prefix))
				},
			)
		} else {
			info = Path.read_utf8!("/proc/cpuinfo")?.split_on("\n\n").first()?
			info.split_on("\n").keep_if(|line| line.starts_with("model name") or line.starts_with("microcode"))
		}
		if hardware.is_empty() {
			return Err(TimingHostIdentity)
		}
		settings = if host == "Darwin" {
			version = Script.command("sw_vers").output!(["-buildVersion"])?
			power = Script.command("pmset").output!(["-g", "batt"])?.split_on("\n").first()?
			"${version} | ${power} | native scheduler"
		} else {
			cpus = ComparisonOptions.affinity(Path.read_utf8!("/proc/self/status")?)?
			Str.inspect(cpus)
		}
		Ok(Dict.from_list([("platform", system_release), ("arch", arch), ("settings", settings), ("hardware", Str.join_with(hardware, "\n"))]))
	}

	load_peer_baseline! : { baseline : Path, digest : Path } => Try(BenchmarkTimingCache.Cache, _)
	load_peer_baseline! = |{ baseline, digest }| {
		if !Path.exists!(baseline)? or !Path.exists!(digest)? {
			return Err(MissingPeerBaseline({ path: Path.display(baseline), refresh: "blueprint run benchmark-peers" }))
		}
		if hash!(baseline)? != Path.read_utf8!(digest)?.trim() {
			return Err(PeerBaselineDigestMismatch)
		}
		Json.parse(Path.read_utf8!(baseline)?)
	}

	hash! : Path => Try(Str, _)
	hash! = |path| Script.command("sha256sum").output!([Path.to_os_str(path)])?.split_on(" ").first()

	collect_sources! : Path, Dict(Str, Str) => Try(Dict(Str, Str), _)
	collect_sources! = |folder, sources| {
		var $sources = sources
		for path in Path.list!(folder)? {
			name = Path.filename(path)?.to_str()?
			if !["target", "targets"].contains(name) {
				if Path.is_dir!(path)? {
					$sources = collect_sources!(path, $sources)?
				} else {
					$sources = $sources.insert(Path.display(path), hash!(path)?)
				}
			}
		}
		Ok($sources)
	}
}
