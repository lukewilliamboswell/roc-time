## Count object members after the built-in decoder has admitted valid JSON.
## For a fully required typed output schema, equality plus the same member
## count rejects unknown/duplicate members that record decoding could skip.
JsonShape := [].{
	keys : Str -> U64
	keys = |source| {
		var $quoted = Bool.False
		var $escaped = Bool.False
		var $count = 0.U64
		for byte in source.to_utf8() {
			if $quoted {
				if $escaped {
					$escaped = Bool.False
				} else if byte == '\\' {
					$escaped = Bool.True
				} else if byte == '"' {
					$quoted = Bool.False
				}
			} else if byte == '"' {
				$quoted = Bool.True
			} else if byte == ':' {
				$count = $count + 1
			}
		}
		$count
	}
}

## Count nested keys without counting colons in strings.
expect JsonShape.keys("{\"a\":\"b:c\",\"d\":{\"e\":[]}}") == 3

## Ignore escaped quotes and colons inside strings.
expect JsonShape.keys("{\"a\":\"quoted \\\" : value\"}") == 1

## Arrays without objects have no keys.
expect JsonShape.keys("[]") == 0
