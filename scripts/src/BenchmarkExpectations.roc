import cli.Path
import BenchmarkOptions
import Script

## Replay reviewed per-case oracle observations without a generator or peer.
BenchmarkExpectations := [].{
	Case : { text : Str, day : I64, microseconds : I64, canonical : Str }
	Reference : { cases : List(Case), checksums : Dict(Str, U64) }
	Profile : { corpus_sha256 : Str, checksums_sha256 : Str }
	Manifest : { schema : Str, oracle : Str, generator_sha256 : Str, profiles : Dict(Str, Profile) }
	generator = "scripts/reference_benchmarks.py"
	oracle = "CPython 3.14.3 datetime"
	schema = "per-case-checksums-v1"

	load! : { profile : Str, corpus : Path, iterations : U64 } => Try(Reference, _)
	load! = |{ profile, corpus, iterations }| {
		directory = Path.utf8("benchmarks/comparison/expectations")
		load_from!({ directory, profile, corpus, iterations })
	}

	load_from! : { directory : Path, profile : Str, corpus : Path, iterations : U64 } => Try(Reference, _)
	load_from! = |{ directory, profile, corpus, iterations }| {
		manifest_file = Path.join(directory, "manifest.json")
		require!(manifest_file)?
		manifest : Manifest
		manifest = Json.parse(Path.read_utf8!(manifest_file)?)?
		identity = manifest.profiles.get(profile).map_err(|_| UnknownExpectationProfile(profile))?
		if manifest.schema != schema or manifest.oracle != oracle {
			return Err(InvalidExpectationSchema)
		}
		checksums_file = Path.join(directory, "${profile}.json")
		require!(corpus)?
		require!(checksums_file)?
		if hash!(Path.utf8(generator))? != manifest.generator_sha256 or hash!(corpus)? != identity.corpus_sha256 or hash!(checksums_file)? != identity.checksums_sha256 {
			return Err(ExpectationDigestMismatch(profile))
		}
		cases : List(Case)
		cases = Path.read_utf8!(corpus)?.drop_suffix("\n").split_on("\n").map_try(Json.parse)?
		series : Dict(Str, List(U64))
		series = Json.parse(Path.read_utf8!(checksums_file)?)?
		checksums = totals({ series, count: cases.len(), iterations })?
		Ok({ cases, checksums })
	}
	hash! : Path => Try(Str, _)
	hash! = |path| Script.command("sha256sum").output!([Path.to_os_str(path)])?.split_on(" ").first()
}

require! : Path => Try({}, _)
require! = |path| if (Path.exists!(path)?) Ok({}) else Err(MissingExpectations(Path.display(path)))

totals : { series : Dict(Str, List(U64)), count : U64, iterations : U64 } -> Try(Dict(Str, U64), [InvalidExpectationValues])
totals = |{ series, count, iterations }| {
	if count < 1 or count > 4096 or iterations < 1 or iterations > 10000000 or series.len() != BenchmarkOptions.modes.len() {
		return Err(InvalidExpectationValues)
	}
	cycles = iterations // count
	tail = U64.rem_by(iterations, count)
	var $checksums = Dict.empty()
	for mode in BenchmarkOptions.modes {
		values = series.get(mode).map_err(|_| InvalidExpectationValues)?
		if values.len() != count or values.any(|value| value > 18446744073709551615 // 10000000) {
			return Err(InvalidExpectationValues)
		}
		sum = values.fold(0, |acc, value| acc + value)
		remainder = values.take_first(tail).fold(0, |acc, value| acc + value)
		$checksums = $checksums.insert(mode, cycles * sum + remainder)
	}
	Ok($checksums)
}
