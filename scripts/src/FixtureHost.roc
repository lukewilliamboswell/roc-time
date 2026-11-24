import cli.Cmd
import cli.Duration
import cli.OsStr
import cli.Path
import Script

## Prepare the real instrumented host. The compiler requires copies of its
## link inputs inside the ignored platform targets directory; canonical build
## artifacts and verified downloads stay under .roc-time-tmp/fixture-platform.
FixtureHost := [].{

	## Preserve the allocation checks on the November 23 and 24 nightlies.
	## Their default dev lowering adds allocation traffic to these fixtures.
	resource_build_flags : Str, Str -> List(Str)
	resource_build_flags = |version, mode| {
		affected_nightlies = ["Roc compiler version nightly-2026-11-23-b5c77fc", "Roc compiler version nightly-2026-11-24-ff5e544"]
		if (mode == "dev" and affected_nightlies.contains(version)) ["--specialize=yes"] else []
	}

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
		Cmd.new(OsStr.from_str(zig)).args((build_args).map(OsStr.from_str)).env(OsStr.from_str("ZIG_GLOBAL_CACHE_DIR"), OsStr.from_str("${Path.display(work)}/global-cache")).timeout(Duration.millis(300000)).call!()?
		destination = Path.join(work, "targets/${target}")
		Path.create_all!(destination)?
		Path.copy!(Path.join(work, "build/lib/libhost.a"), Path.join(destination, "libhost.a"))?
		if target == "x64musl" {
			# This compiler emits static PIE. rcrt1 relocates it before musl starts;
			# regular crt1 enters the host with unresolved pointers.
			archive = Path.join(work, "link-inputs-x64musl.tar")
			archive_hash = "1e6ccfa2a16797526dcb5159b49963ad78bb77346231ff91782c12a37159b914"
			if !Path.exists!(archive)? {
				url = "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/linker-inputs-sha256-87607c935001a854a31d2f954583e0f331dfcd16920ef7fde8824adf795ce502/link-inputs-x64musl.tar"
				Cmd.new("curl").args([
					"--fail",
					"--location",
					"--max-time",
					"60",
					"--max-filesize",
					"6615040",
					OsStr.from_str(url),
					"--output",
					Path.to_os_str(archive),
				]).call!()?
			}
			archive_actual = Script.command("sha256sum").output!([Path.to_os_str(archive)])?
			if !archive_actual.starts_with("${archive_hash} ") {
				return Script.fail!("instrumented link-input archive integrity mismatch")
			}
			for (name, expected) in [
				("rcrt1.o", "acb752dda83e2eb0cfe37c5217bb38fc624211ed9c5a9e7d59f4dcaec6fbde3d"),
				("libc.a", "8fcb34d47aa311d8ef9331313f881014da2d67bb62afed3bb0f096b18576968e"),
			] {
				file = Path.join(destination, name)
				member = Cmd.new("tar").args(["-xOf", Path.to_os_str(archive), OsStr.from_str(name)]).timeout(Duration.millis(30000)).output_limit(MaxBytes(2097152)).stdout(Capture).stderr(Capture).run!()?
				if member.status != Exited(0) {
					return Script.fail!("instrumented link-input extraction failed: ${name}")
				}
				Path.write_bytes!(file, member.stdout_bytes)?
				actual = Script.command("sha256sum").output!([Path.to_os_str(file)])?
				if !actual.starts_with("${expected} ") {
					return Script.fail!("instrumented link-input integrity mismatch: ${name}")
				}
			}
		}
		platform_directory = Path.utf8("tests/platform/targets/${target}")
		Path.create_all!(platform_directory)?
		for name in if target == "x64musl" {
			["libhost.a", "rcrt1.o", "libc.a"]
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
