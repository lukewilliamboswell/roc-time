#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import cli.Env
import cli.OsStr
import cli.Path
import src/ApiInventory
import src/Script

main! = |_args| {
	if Path.read_bytes!("tzdb/Database.roc")? != Path.read_bytes!("tzdb/package/Database.roc")? {
		return Script.fail!("regenerate the distributable zone database module")
	}
	nightly = Script.roc_nightly!()?
	Path.create_all!(".roc-time-tmp")?
	work = Env.create_temp_dir_in!(Path.absolute!(".roc-time-tmp")?, "api-evidence-")?
	for (root, folder) in [("package/main.roc", "core"), ("tzdb/package/main.roc", "zones")] {
		output = Path.join(work, folder)
		nightly.run!(["docs", OsStr.from_str(root), OsStr.from_str("--output=${Path.display(output)}")])?
		count = check_pages!(output)?
		if count == 0 {
			return Script.fail!("no public entries generated for ${root}")
		}
		Script.info!("PASS", "${count.to_str()} documented API entries for ${root}")?
	}
	for (owner, names) in [
		("Calendar.Date", ["from_fields", "as_gregorian", "in_calendar", "same_day", "to_hash"]),
		("Calendar.Arithmetic", ["shift_day"]),
		("Calendar.Delta", ["from_components", "to_components", "days", "months"]),
		("Calendar.Value", ["minute", "fractional_second", "resolution", "bounds", "to_hash"]),
		("TimedSchedule.Endings", ["new", "definition", "is_eq", "to_hash"]),
		("Database", ["get"]),
	] {
		page = if owner == "Database" {
			Path.join(work, "zones/index.html")
		} else {
			family = owner.split_on(".").first() ?? ""
			Path.join(work, "core/${family}/index.html")
		}
		html = Path.read_utf8!(page)?
		ApiInventory.methods(html, owner, names)?
		method = "${owner}.${names.first() ?? ""}"
		anchor_removed = html.replace_each("id=\"${method}\"", "id=\"removed-method\"")
		if ApiInventory.methods(anchor_removed, owner, names).is_ok() {
			return Script.fail!("missing-anchor control passed for ${method}")
		}
		# Changing the fragment everywhere preserves the method's ID, while
		# removing its search destination. The same checker must reject it.
		search_removed = html.replace_each("#${method}\"", "#removed-method\"")
		if ApiInventory.methods(search_removed, owner, names).is_ok() {
			return Script.fail!("missing-search control passed for ${method}")
		}
	}
	Script.info!("PASS", "nested API methods, search entries and missing-entry controls")
}

check_pages! = |directory| {
	var $count = 0.U64
	for entry in Path.list!(directory)? {
		if Path.is_dir!(entry)? {
			$count = $count + check_pages!(entry)?
		} else if Path.display(entry).ends_with(".html") {
			$count = $count + ApiInventory.read(Path.read_utf8!(entry)?)?.entries.len()
		}
	}
	Ok($count)
}
