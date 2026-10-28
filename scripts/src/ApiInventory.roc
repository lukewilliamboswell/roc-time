import DocLinks

## Audit the compiler's canonical HTML entry and search markup. This is an
## output contract check, not a general HTML parser or a source-doc generator.
ApiInventory := [].{
	Inventory : { entries : List(Str), search : List(Str) }

	read : Str -> Try(Inventory, [MalformedHtml, MissingDocs(Str)])
	read = |html| {
		var $stack = []
		var $depth = 0.U64
		var $owner = ""
		var $entries = []
		var $search = []
		var $documented = []
		for token in html.split_on("<").drop_first(1) {
			tag = token.split_on(">").first() ?? ""
			body = token.drop_prefix("${tag}>")
			kind = tag.split_on(" ").first() ?? ""
			if kind == "article" {
				id = DocLinks.attributes(tag, "id").first() ?? ""
				$stack = $stack.append(id)
				if !id.is_empty() {
					$entries = $entries.append(id)
				}
			} else if kind == "/article" {
				if $stack.is_empty() {
					return Err(MalformedHtml)
				}
				$stack = $stack.take_first($stack.len() - 1)
			} else if kind == "div" {
				if $depth > 0 {
					$depth = $depth + 1
				} else if (DocLinks.attributes(tag, "class").first() ?? "").split_on(" ").contains("entry-doc") {
					$owner = $stack.last() ?? ""
					$depth = 1
				}
			} else if kind == "/div" and $depth > 0 {
				$depth = $depth - 1
				if $depth == 0 {
					$owner = ""
				}
			} else if kind == "a" and (DocLinks.attributes(tag, "class").first() ?? "").split_on(" ").contains("type-ahead-link") {
				href = DocLinks.attributes(tag, "href").first() ?? ""
				$search = $search.append(href.split_on("#").last() ?? "")
			}
			if $depth > 0 and !$owner.is_empty() and !body.replace_each("&nbsp;", " ").trim().is_empty() {
				$documented = $documented.append($owner)
			}
		}
		if !$stack.is_empty() or $depth != 0 {
			return Err(MalformedHtml)
		}
		for entry in $entries {
			if !$documented.contains(entry) {
				return Err(MissingDocs(entry))
			}
		}
		Ok({ entries: $entries, search: $search })
	}

	methods : Str, Str, List(Str) -> Try({}, [MalformedHtml, MissingDocs(Str), MissingMethod(Str)])
	methods = |html, owner, names| {
		inventory = read(html)?
		for name in names {
			method = "${owner}.${name}"
			if !inventory.entries.contains(method) or !inventory.search.contains(method) {
				return Err(MissingMethod(method))
			}
		}
		Ok({})
	}
}

parent = "<article id=\"Family\"><div class=\"entry-doc\"><p>Family meaning.</p></div>"
expect ApiInventory.read("${parent}<article id=\"Family.new\"></article></article>") == Err(MissingDocs("Family.new"))
expect ApiInventory.read("${parent}<article id=\"Family.new\"><div class=\"entry-doc\"> </div></article></article>") == Err(MissingDocs("Family.new"))
expect ApiInventory.read("${parent}<article id=\"Family.new\"><div class=\"entry-doc\"><p>Construct a value.</p></div></article></article>").map_ok(|inventory| inventory.entries.len()) == Ok(2)
expect ApiInventory.read("<article id=\"Unclosed\">") == Err(MalformedHtml)
expect ApiInventory.methods("${parent}</article>", "Family", ["new"]) == Err(MissingMethod("Family.new"))
