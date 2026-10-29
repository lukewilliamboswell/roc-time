import cli.Path
import DocLinks
import Files
import Script

## Executable checks for the authored manual, separate from compiler-generated APIs.
Manual := [].{

	## Validate actual HTML/PDF output. Source comparison is a candidate-build gate;
	## restored immutable archives are checked without comparing to today's sources.
	verify! : Path, Bool => Try({}, _)
	verify! = |site, compare_sources| {
		entries = Path.list!(site)?
		files = entries.map(Files.name)
		for required in [
			"index.html",
			"index.md",
			"llms.txt",
			"getting-started.html",
			"booking.html",
			"calendar-zones.html",
			"schedules.html",
			"profiles.html",
			"api.html",
			"versions.html",
			"roc-time.pdf",
		] {
			if !files.contains(required) {
				return Script.fail!("manual is missing ${required}")
			}
		}
		pages = entries.keep_if(|path| Files.name(path).ends_with(".html"))
			.map_try!(|path| Ok({ name: Files.name(path), html: Path.read_utf8!(path)? }))?
		for problem in DocLinks.problems(pages, files) {
			return Script.fail!(problem)
		}
		for page in pages {
			markdown = Str.replace_each(page.name, ".html", ".md")
			if !files.contains(markdown) or !page.html.contains("text/markdown") or !page.html.contains("llms.txt") {
				return Script.fail!("${page.name}: Markdown export or discovery links are missing")
			}
		}
		pdf = Path.join(site, "roc-time.pdf")
		if !Str.from_utf8_lossy(Path.read_bytes!(pdf)?.take_first(8)).starts_with("%PDF-2.0") {
			return Script.fail!("manual is not PDF 2.0")
		}
		text = normalize(Script.command("pdftotext").output!(["-layout", Path.to_os_str(pdf), "-"])?)
		destinations = Script.command("pdfinfo").output!(["-dests", Path.to_os_str(pdf)])?
		for page in pages {
			heading = page.html.split_on("<h1").get(1) ?? ""
			tag = heading.split_on(">").first() ?? ""
			destination = DocLinks.attributes(tag, "id").first() ?? ""
			if destination.is_empty() or !destinations.contains("\"${destination}\"") {
				return Script.fail!("PDF lacks chapter destination for ${page.name}")
			}
		}
		for title in [
			"Time for real applications",
			"Run your first application",
			"Find free booking windows",
			"Work with dates and clock changes",
			"Generate and exchange schedules",
			"Know the supported scope",
			"Find the right API",
			"Keep examples and versions together",
		] {
			if !text.contains(title) {
				return Script.fail!("PDF lost chapter text: ${title}")
			}
		}
		if compare_sources {
			for page in pages {
				if page.name != "index.html" {
					stem = Str.replace_each(page.name, ".html", ".adoc")
					source = Path.read_utf8!(Path.join("docs", stem))?
					var $blocks = DocLinks.source_blocks(source)
					# Release listings live in included authored files. Check their
					# bytes too, rather than treating the chapter as having none.
					for line in source.split_on("\n") {
						if line.starts_with("include::releases/") {
							file = line.drop_prefix("include::").split_on("[").first() ?? ""
							$blocks = $blocks.concat(DocLinks.source_blocks(Path.read_utf8!(Path.join("docs", file))?))
						}
					}
					blocks = $blocks
					if DocLinks.code_blocks(page.html) != blocks {
						return Script.fail!("${page.name}: rendered source bytes differ")
					}
					markdown = Path.read_utf8!(Path.join(site, Str.replace_each(page.name, ".html", ".md")))?
					for block in blocks {
						if !markdown.contains(block.trim_end()) {
							return Script.fail!("${page.name}: Markdown lost source bytes")
						}
						for line in block.split_on("\n").keep_if(|line| !Str.trim(line).is_empty()) {
							if !text.contains(normalize(line)) {
								return Script.fail!("PDF lost source text: ${line}")
							}
						}
					}
				}
			}
		}
		Script.info!({
			label: "PASS",
			message: "manual: ${pages.len().to_str()} HTML/Markdown pages, discovery links, local fragments, PDF chapters and source text",
		})
	}
}

normalize : Str -> Str
normalize = |text| Str.join_with(
	text.replace_each("\n", " ").replace_each("\r", " ").replace_each("\t", " ").split_on(" ").keep_if(|word| !word.is_empty()),
	" ",
)
