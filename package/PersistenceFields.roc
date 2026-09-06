## Shared bounded flat-string JSON container driver. Wrapping nominal types
## pass this parser their own maximum field count and delegate builtin JSON
## framing to the encoding. The caller checks raw byte limits before Json.parse.
## Nested containers fail at parse_str without recursive traversal; excess fields
## fail before the next string is decoded or appended. Counted encodings are
## outside this JSON-specific profile.
PersistenceFields := [].{
	parser : encoding, U64 -> (state -> Try({ value : List(Str), rest : state }, [Encoding(err), TooManyFields, UnsupportedContainer, ..]))
		where [
			encoding.parse_list_start : encoding, state -> Try([Counted({ len : U64, rest : state }), Uncounted(state)], err),
			encoding.parse_list_next : encoding, state -> Try([Item(state), Done(state)], err),
			encoding.parse_str : encoding, state -> Try({ value : Str, rest : state }, err),
			encoding.parse_list_after_item : encoding, state -> Try([Continue(state), Done(state)], err),
		]
	parser = |encoding, max_fields| {
		Encoding : encoding
		|state| {
			opened = match Encoding.parse_list_start(encoding, state) {
				Ok(v) => v
				Err(e) => return Err(Encoding(e))
			}
			var $rest = match opened {
				Uncounted(s) => s
				Counted(_) => return Err(UnsupportedContainer)
			}
			var $entries = []
			var $done = Bool.False
			while !$done {
				next = match Encoding.parse_list_next(encoding, $rest) {
					Ok(v) => v
					Err(e) => return Err(Encoding(e))
				}
				match next {
					Done(s) => {
						$rest = s
						$done = True
					}
					Item(s) => {
						if $entries.len() >= max_fields {
							return Err(TooManyFields)
						}
						field = match Encoding.parse_str(encoding, s) {
							Ok(v) => v
							Err(e) => return Err(Encoding(e))
						}
						$entries = $entries.append(field.value)
						after = match Encoding.parse_list_after_item(encoding, field.rest) {
							Ok(v) => v
							Err(e) => return Err(Encoding(e))
						}
						match after {
							Continue(s2) => {
								$rest = s2
							}
							Done(s2) => {
								$rest = s2
								$done = True
							}
						}
					}
				}
			}
			Ok({ value: $entries, rest: $rest })
		}
	}
}
