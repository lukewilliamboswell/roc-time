import cli.Cmd
import cli.OsStr
import cli.Path
import Script

## Prepare the real instrumented host. The compiler requires copies of its
## link inputs inside the ignored platform targets directory; canonical build
## artifacts and verified downloads stay under .roc-time-tmp/fixture-platform.
FixtureHost := [].{
	build! : () => Try(Str, _)
	build! = || {
		host = (Script.command("uname").output!(["-s"])?, Script.command("uname").output!(["-m"])?)
		target = match host {
			("Linux", "x86_64") => "x64musl"
			("Darwin", "arm64") => "arm64mac"
			_ => return Script.fail!("unverified instrumented fixture host ${Str.inspect(host)}")
		}
		zig = Script.env_str!("ZIG") ?? "zig"
		if Script.command(OsStr.from_str(zig)).output!(["version"])? != "0.17.0" {
			return Script.fail!("instrumented host requires Zig 0.17.0")
		}
		work = Path.absolute!(".roc-time-tmp/fixture-platform")?
		Path.create_all!(work)?
		args = [
			"build",
			"--build-file",
			Path.display(Path.absolute!("tests/platform/build.zig")?),
			"--prefix",
			"${Path.display(work)}/build",
			"--cache-dir",
			"${Path.display(work)}/cache",
			"-Doptimize=ReleaseFast",
		]
		build_args = if target == "x64musl" {
			args.append("-Dtarget=x86_64-linux-musl")
		} else {
			args
		}
		Cmd.new_str(zig).args_str(build_args).env_str("ZIG_GLOBAL_CACHE_DIR", "${Path.display(work)}/global-cache").timeout_ms(300000).exec_cmd!()?
		destination = Path.join(work, "targets/${target}")
		Path.create_all!(destination)?
		Path.copy!(Path.join(work, "build/lib/libhost.a"), Path.join(destination, "libhost.a"))?
		if target == "x64musl" {
			for (name, expected) in [
				("crt1.o", "ffb51a69191a69fc34acaec1003fabe245d8841da7036d124d3445718415f9ea"),
				("libc.a", "85f5eb2316bc6f86be7bd66008488c7d2eca290942b01ad2e86f02f8b5e8c90f"),
			] {
				file = Path.join(destination, name)
				if !Path.exists!(file)? {
					url = "https://raw.githubusercontent.com/lukewilliamboswell/roc-platform-template-zig/d4db636a2f606edf5ae4803f84588f7a5207d53a/platform/targets/x64musl/${name}"
					Cmd.new("curl").args([
						"--fail",
						"--location",
						"--max-time",
						"60",
						"--max-filesize",
						"16777216",
						OsStr.from_str(url),
						"--output",
						Path.to_os_str(file),
					]).exec_cmd!()?
				}
				actual = Script.command("sha256sum").output!([Path.to_os_str(file)])?
				if !actual.starts_with("${expected} ") {
					return Script.fail!("instrumented link-input integrity mismatch: ${name}")
				}
			}
		}
		platform_directory = Path.utf8("tests/platform/targets/${target}")
		Path.create_all!(platform_directory)?
		for name in if target == "x64musl" {
			["libhost.a", "crt1.o", "libc.a"]
		} else {
			["libhost.a"]
		} {
			Path.copy!(Path.join(destination, name), Path.join(platform_directory, name))?
		}
		Script.info!({
			label: "HOST",
			message: "Zig 0.17.0 ReleaseFast, debug symbols retained; ${target}",
		})?
		Ok(target)
	}
}
