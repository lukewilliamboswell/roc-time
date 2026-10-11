app [main!] {
	pf: platform "https://github.com/lukewilliamboswell/basic-ssg/releases/download/0.13.0/2JyANXb36FC5N1DuzdfGEK6XC7QxqYbjZHegS98VbkFK.tar.zst",
}
import pf.SSG
import pf.Path
import pf.OsStr
import Site

main! : List(OsStr) => Try({}, [Exit(I32), PagesError(Str), ParseError(Str), WriteError(Str), UnknownPage(Str)])
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
