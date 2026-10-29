#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import cli.Cmd
import cli.OsStr
import cli.Path
import cli.Stdout
import src/Script
import src/ZoneArchive

main! = |args| {
	texts = args.map(OsStr.display)
	if texts == ["--help"] {
		return Script.info!("usage:", "blueprint run measure-zone-data -- [WHEEL] [--smoke]")
	}
	smoke = texts.contains("--smoke")
	positional = texts.keep_if(|text| text != "--smoke")
	wheel = match positional {
		[file] if !file.starts_with("--") => Path.absolute!(Path.utf8(file))?
		[] if smoke => {
			file = Path.absolute!(".roc-time-tmp/measurement-smoke/tzdata.whl")?
			Path.create_all!(".roc-time-tmp/measurement-smoke")?
			if !Path.exists!(file)? {
				Cmd.new("curl").args(["--fail", "--location", "--max-time", "30", "--max-filesize", "1048576", OsStr.from_str(ZoneArchive.url), "--output", Path.to_os_str(file)]).timeout_ms(40000).exec_cmd!()?
			}
			file
		}
		_ => return Err(Arguments)
	}
	wheel_bytes = U64.from_str(Script.command("stat").output!(["-c", "%s", Path.to_os_str(wheel)])?)?
	if wheel_bytes > 1048576 {
		return Err(WheelSize)
	}
	digest = Script.command("sha256sum").output!([Path.to_os_str(wheel)])?
	if !digest.starts_with("${ZoneArchive.sha256} ") {
		return Err(WheelIntegrity)
	}
	inventory = Script.command("unzip").output!(["-lv", Path.to_os_str(wheel)])?
	entries = ZoneArchive.entries(inventory)?
	var $distinct = []
	var $selected = Dict.empty()
	var $expanded = 0.U64
	var $compressed = 0.U64
	var $count = 0.U64
	for entry in entries {
		result = Cmd.new("unzip").args(["-p", Path.to_os_str(wheel), OsStr.from_str(entry.name)]).timeout_ms(5000).output_limit(1048576).stdout(Capture).stderr(Capture).run!()?
		if result.status != Exited(0) or result.stdout_bytes.len() != entry.expanded {
			return Err(PayloadRead)
		}
		data = result.stdout_bytes
		if data.take_first(4) == ['T', 'Z', 'i', 'f'] {
			$count = $count + 1
			$expanded = $expanded + entry.expanded
			$compressed = $compressed + entry.compressed
			if !$distinct.contains(data) {
				$distinct = $distinct.append(data)
			}
			name = entry.name.drop_prefix("tzdata/zoneinfo/")
			if ["Australia/Melbourne", "America/New_York", "Europe/London", "Pacific/Apia"].contains(name) {
				$selected = $selected.insert(name, data.len())
			}
		}
	}
	if $selected.len() != 4 or $selected.values().any(|size| size == 0) or $count < 4 or $distinct.len() > $count {
		return Err(ReportInvariant)
	}
	report = { source: "tzdata 2025.2 / IANA 2025b", wheel_sha256: ZoneArchive.sha256, wheel_bytes, tzif_entry_count: $count, tzif_uncompressed_bytes: $expanded, tzif_zip_payload_bytes: $compressed, byte_distinct_payload_count: $distinct.len(), byte_distinct_payload_bytes: $distinct.fold(0.U64, |total, data| total + data.len()), selected_tzif_bytes: $selected, limits: "ZIP entry payload sizes exclude archive metadata. Byte-distinct payload count is not canonical zone count. No Roc source, compiler, linked binary or runtime memory measurements." }
	Stdout.line!(Json.to_str(report))
}
