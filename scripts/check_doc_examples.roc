#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import cli.Env
import cli.Path
import cli.OsStr
import src/DocExamples
import src/Files
import src/Script

main! = |_args| {
	sources = Files.direct_roc_files!("package")?.map_try!(|path| Ok({ path: Path.display(path), source: Path.read_utf8!(path)? }))?
	listings = DocExamples.collect(sources)?
	if listings.bodies.is_empty() {
		return Script.fail!("no executable public documentation listings found")
	}
	Path.create_all!(".roc-time-tmp")?
	work = Env.create_temp_dir_in!(Path.absolute!(".roc-time-tmp")?, "doc-listings-")?
	entry = Path.join(work, "main.roc")
	Path.write_utf8!(entry, "app [main!] { time: \"../../package/main.roc\" }\n${Str.join_with(listings.import_lines, "\n")}\nmain! = |_| Ok({})\n\n${Str.join_with(listings.bodies, "\n\n")}\n")?
	nightly = Script.roc_nightly!()?
	for operation in ["check", "test"] {
		nightly.run!([OsStr.from_str(operation), Path.to_os_str(entry)])?
	}
	Script.info!("PASS", "${listings.bodies.len().to_str()} executable public documentation listings")
}
