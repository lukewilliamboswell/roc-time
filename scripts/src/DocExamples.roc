## Extract complete Roc listings from public documentation comments. The real
## compiler subsequently checks and executes them through the public package.
DocExamples := [].{
	collect : List({ path : Str, source : Str }) -> Try({ import_lines : List(Str), bodies : List(Str) }, [UnclosedListing(Str)])
	collect = |sources| {
		var $import_lines = []
		var $bodies = []
		for source in sources {
			var $inside = Bool.False
			var $body = []
			for line in source.source.split_on("\n") {
				trimmed = line.trim_start()
				if trimmed.starts_with("##") {
					comment = trimmed.drop_prefix("##").drop_prefix(" ")
					if !$inside and comment == "```roc" {
						$inside = Bool.True
					} else if $inside and comment == "```" {
						$bodies = $bodies.append("# Documentation listing from ${source.path}\n${Str.join_with($body, "\n")}")
						$body = []
						$inside = Bool.False
					} else if $inside {
						if comment.starts_with("import ") {
							if !$import_lines.contains(comment) {
								$import_lines = $import_lines.append(comment)
							}
						} else {
							$body = $body.append(comment)
						}
					}
				}
			}
			if $inside {
				return Err(UnclosedListing(source.path))
			}
		}
		Ok({ import_lines: $import_lines, bodies: $bodies })
	}
}

## Collect imports and executable Roc listings.
expect DocExamples.collect([{ path: "A.roc", source: "## ```roc\n## import time.A\n## expect A.value == 1\n## ```\n" }]).map_ok(|value| (value.import_lines, value.bodies.len())) == Ok((["import time.A"], 1))

## Reject an unterminated Roc listing.
expect DocExamples.collect([{ path: "A.roc", source: "## ```roc\n## expect Bool.True\n" }]) == Err(UnclosedListing("A.roc"))

## Leave non-Roc listings out of executable evidence.
expect DocExamples.collect([{ path: "A.roc", source: "## ```text\n## uncompiled text\n## ```\n" }]) == Ok({ import_lines: [], bodies: [] })
