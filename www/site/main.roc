app [main!] {
	pf: platform "https://github.com/lukewilliamboswell/basic-ssg/releases/download/0.11.0/3vqgmE9dzxoPRNgCbUYrfJhcsyV1DKpi8Q8qKAsSt1Br.tar.zst",
	roc: "nightly-2026-09-06-d85e877",
}
import pf.SSG
import pf.Path
import pf.OsStr exposing [OsStr]
import Site

main! : List(OsStr) => Try({}, [Exit(I32), PagesError(Str), ParseError(Str), WriteError(Str), UnknownPage(Str), ..])
main! = |args| match args.drop_first(1) {
	[source, destination] => {
		pages = SSG.markdown_pages!(Path.from_os_str(source))?
		for page in pages {
			body = SSG.parse_markdown!(page.source_path)?
			html = Site.render(page.url, body)?
			SSG.write_file!({ output_dir: Path.from_os_str(destination), output_path: page.output_path, content: html })?
		}
		Ok({})
	}
	_ => Err(Exit(1))
}
