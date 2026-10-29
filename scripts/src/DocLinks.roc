## Checks for the shared renderer's emitted HTML, without interpreting AsciiDoc.
DocLinks := [].{
	Page : { name : Str, html : Str }

	## Quoted attributes in the renderer's canonical double-quoted HTML output.
	attributes : Str, Str -> List(Str)
	attributes = |html, name| html.split_on(" ${name}=\"").drop_first(1).map(|rest| rest.split_on("\"").first() ?? "")

	## Validate every local link and fragment, duplicate IDs, headings and skip links.
	problems : List(Page), List(Str) -> List(Str)
	problems = |pages, files| {
		var $problems = []
		for page in pages {
			ids = attributes(page.html, "id")
			if ids.any(|id| ids.count_if(|other| other == id) != 1) {
				$problems = $problems.append("${page.name}: duplicate HTML ID")
			}
			if page.html.split_on("<title>").len() != 2 or page.html.split_on("<h1 ").len() != 2 {
				$problems = $problems.append("${page.name}: missing or repeated title/heading")
			}
			if !ids.contains("content") or !attributes(page.html, "href").contains("#content") {
				$problems = $problems.append("${page.name}: missing keyboard skip link")
			}
			for href in attributes(page.html, "href") {
				if !(href.starts_with("https://") or href.starts_with("mailto:")) {
					parts = href.split_on("#")
					path = parts.first() ?? ""
					fragment = parts.get(1) ?? ""
					name = if (path.is_empty()) page.name else path
					if name.starts_with("/") or name.contains("..") or name.contains(":") or parts.len() > 2 or !files.contains(name) {
						$problems = $problems.append("${page.name}: missing or unsafe target ${href}")
					} else if !fragment.is_empty() {
						target = pages.find_first(|candidate| candidate.name == name)
						if !(target.map_ok(|candidate| attributes(candidate.html, "id").contains(fragment)) ?? Bool.False) {
							$problems = $problems.append("${page.name}: missing fragment ${href}")
						}
					}
				}
			}
		}
		$problems
	}

	## Exact visible code, after removing the shared highlighter's span markup.
	code_blocks : Str -> List(Str)
	code_blocks = |html| html.split_on("<pre").drop_first(1).map(
		|rest| {
			body = rest.split_on("</pre>").first() ?? ""
			var $inside_tag = Bool.True
			var $bytes = []
			for byte in body.to_utf8() {
				if byte == '<' {
					$inside_tag = Bool.True
				} else if byte == '>' {
					$inside_tag = Bool.False
				} else if !$inside_tag {
					$bytes = $bytes.append(byte)
				}
			}
			Str.from_utf8_lossy($bytes)
				.replace_each("&lt;", "<").replace_each("&gt;", ">").replace_each("&quot;", "\"")
				.replace_each("&#39;", "'").replace_each("&amp;", "&")
		},
	)

	## Listing bodies in this manual's plain, untagged AsciiDoc source blocks.
	source_blocks : Str -> List(Str)
	source_blocks = |source| {
		var $blocks = []
		var $body = Bool.False
		for part in source.split_on("----\n").drop_first(1) {
			$body = !$body
			if $body {
				$blocks = $blocks.append(part)
			}
		}
		$blocks
	}
}

sample = "<title>T</title><h1 id=\"start\">T</h1><main id=\"content\"><a href=\"#content\">Skip</a></main>"

## Accept links to existing local anchors.
expect DocLinks.problems([{ name: "index.html", html: sample }], ["index.html"]) == []

## Report missing local files.
expect !DocLinks.problems([{ name: "index.html", html: "${sample}<a href=\"missing.html\">Bad</a>" }], ["index.html"]).is_empty()

## Report missing local fragments.
expect !DocLinks.problems([{ name: "index.html", html: "${sample}<a href=\"#absent\">Bad</a>" }], ["index.html"]).is_empty()

## Report duplicate anchors.
expect !DocLinks.problems([{ name: "index.html", html: "${sample}<p id=\"start\">Bad</p>" }], ["index.html"]).is_empty()

## Decode rendered code text without markup.
expect DocLinks.code_blocks("<pre><code><span>roc</span> main.roc &amp; x\n</code></pre>") == ["roc main.roc & x\n"]

## Extract source blocks without surrounding prose.
expect DocLinks.source_blocks("[source,sh]\n----\nroc main.roc\n----\nAfter\n") == ["roc main.roc\n"]
