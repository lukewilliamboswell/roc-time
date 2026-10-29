## Bounded, exact JSONL transport admission. Temporal interpretation stays in
## the real public package and the independently generated expected corpus.
OracleCases := [].{
	Case : { id : Str, operation : Str, input : List(Str), expected : List(Str), evidence : Str }
	load : Str, U64, Str -> Try(List(Case), [OracleRecord])
	load = |text, count, name| {
		if text.count_utf8_bytes() > 4194304 or count == 0 or count > 4096 {
			return Err(OracleRecord)
		}
		lines = if (text.ends_with("\n")) text.drop_suffix("\n").split_on("\n") else text.split_on("\n")
		if lines.len() != count {
			return Err(OracleRecord)
		}
		lines.map_with_index(
			|line, index| {
				if line.count_utf8_bytes() > 16384 {
					return Err(OracleRecord)
				}
				case : Case
				case = Json.parse(line).map_err(|_| OracleRecord)?
				keys = record_keys(line)?
				if keys.len() != 5 or ["id", "operation", "input", "expected", "evidence"].any(|key| keys.count_if(|found| found == key) != 1) or case.id != index.to_str() or case.evidence.is_empty() or case.operation.is_empty() or !case.operation.to_utf8().all(|b| (b >= 'a' and b <= 'z') or b == '_') or case.operation.starts_with("_") {
					return Err(OracleRecord)
				}
				for values in [case.input, case.expected] {
					if values.is_empty() or values.len() > 32 or values.any(|value| value.is_empty() or value.count_utf8_bytes() > 256 or value.to_utf8().any(|b| b == '\t' or b == '\r' or b == '\n' or b == 0)) {
						return Err(OracleRecord)
					}
				}
				validate(case, name)?
				Ok(case)
			},
		).map_try(|result| result)
	}
	validate : Case, Str -> Try({}, [OracleRecord])
	validate = |case, name| {
		values = case.input
		expected = case.expected
		get = |items, index| items.get(index).map_err(|_| OracleRecord)
		match name {
			calendar if ["gregorian", "julian"].contains(calendar) => {
				if !["forward", "inverse"].contains(case.operation) or values.len() != (if (case.operation == "forward") 3 else 1) {
					return Err(OracleRecord)
				}
				_ = integer(get(values, 0)?)?
				for text in values.drop_first(1) {
					_ = byte(text)?
				}
				match expected {
					["error", error] if ["OutOfRange", "InvalidMonth", "InvalidDay"].contains(error) => {}
					["ok", .. as numbers] if numbers.len() == (if (case.operation == "forward") 1 else 3) => for text in numbers {
						_ = integer(text)?
					}
					_ => return Err(OracleRecord)
				}
			}
			"zones" => {
				if case.operation != "resolve" or values.len() != 8 {
					return Err(OracleRecord)
				}
				first = unsigned(get(values, 0)?)?
				if first > 2 {
					return Err(OracleRecord)
				}
				_ = integer(get(values, 1)?)?
				for text in values.drop_first(2).take_first(5) {
					_ = byte(text)?
				}
				if unsigned(get(values, 7)?)? > 4294967295 {
					return Err(OracleRecord)
				}
				match expected {
					["ok", .. as numbers] if numbers.len() <= 2 => ordered_integers(numbers)?
					_ => return Err(OracleRecord)
				}
			}
			"calendar_pattern" => {
				if case.operation != "pattern" or values.len() != 12 {
					return Err(OracleRecord)
				}
				for (index, low, high) in [(0.U64, 1.I64, 9999.I64), (1, 1, 12), (2, 1, 31), (3, 0, 3), (4, 1, 2147483647), (5, 0, 6)] {
					number = integer(get(values, index)?)?
					if number < low or number > high {
						return Err(OracleRecord)
					}
				}
				_ = unsigned(get(values, 6)?)?
				for value in values.drop_first(7).take_first(4) {
					if value != "-" {
						for part in value.split_on(",") {
							_ = integer(part)?
						}
					}
				}
				weekday = get(values, 11)?
				if weekday != "-" {
					for part in weekday.split_on(",") {
						match part.split_on(":") {
							[ordinal, day] => {
								_ = integer(ordinal)?
								if byte(day)? > 6 {
									return Err(OracleRecord)
								}
							}
							_ => return Err(OracleRecord)
						}
					}
				}
				if expected.len() < 4 or expected.len() > 6 or expected.first() != Ok("ok") {
					return Err(OracleRecord)
				}
				start = integer(get(expected, 1)?)?.to_i128()
				end = integer(get(expected, 2)?)?.to_i128()
				width = end - start
				bitmap = expected.drop_first(3)
				if width < 1 or width > 366 or bitmap.any(|part| part.is_empty() or part.count_utf8_bytes() > 128 or !part.to_utf8().all(|b| b == '0' or b == '1')) or bitmap.fold(0.U64, |sum, part| sum + part.count_utf8_bytes()).to_i128() != width {
					return Err(OracleRecord)
				}
			}
			profile if ["rfc_date", "rfc_timed"].contains(profile) => {
				timed = name == "rfc_timed"
				if case.operation != name or values.len() != 6 {
					return Err(OracleRecord)
				}
				for index in [0.U64, 4, 5] {
					if !date_text(get(values, index)?, timed) {
						return Err(OracleRecord)
					}
				}
				rule = get(values, 1)?
				if rule.is_empty() or !rule.to_utf8().all(|b| b >= 33 and b <= 126) {
					return Err(OracleRecord)
				}
				for index in [2.U64, 3] {
					list = get(values, index)?
					if list != "-" and !list.split_on(",").all(|part| date_text(part, timed)) {
						return Err(OracleRecord)
					}
				}
				match expected {
					["ok", .. as observations] => if timed {
						ordered_integers(observations)?
					} else {
						if !observations.all(|part| date_text(part, Bool.False)) {
							return Err(OracleRecord)
						}
						# Fixed-width ASCII dates sort in chronological order.
						ordered_values(observations.map_try(|text| I64.from_str(text).map_err(|_| OracleRecord))?)?
					}
					_ => return Err(OracleRecord)
				}
			}
			_ => return Err(OracleRecord)
		}
		Ok({})
	}
	compare : Case, Str -> Bool
	compare = |case, output| output == "${Str.join_with([case.id].concat(case.expected), "\t")}\n"
}

integer = |text| {
	number = I64.from_str(text).map_err(|_| OracleRecord)?
	if number.to_str() != text {
		return Err(OracleRecord)
	}
	Ok(number)
}

unsigned = |text| {
	number = U64.from_str(text).map_err(|_| OracleRecord)?
	if number.to_str() != text {
		return Err(OracleRecord)
	}
	Ok(number)
}

byte = |text| {
	number = unsigned(text)?
	if number > 255 {
		return Err(OracleRecord)
	}
	Ok(number)
}

ordered_integers = |texts| ordered_values(texts.map_try(integer)?)

ordered_values = |values| {
	var $prior = []
	for value in values {
		match $prior {
			[prior] if prior >= value => return Err(OracleRecord)
			_ => {}
		}
		$prior = [value]
	}
	Ok({})
}

date_text = |text, timed| {
	bytes = text.to_utf8()
	if !timed {
		bytes.len() == 8 and bytes.all(|b| b >= '0' and b <= '9')
	} else {
		bytes.len() == 16 and bytes.get(8) == Ok('T') and bytes.get(15) == Ok('Z') and bytes.take_first(8).concat(bytes.drop_first(9).take_first(6)).all(|b| b >= '0' and b <= '9')
	}
}

# The built-in decoder handles JSON syntax/escapes. This bounded lexer records
# outer keys before decoding can discard an unknown or repeated field.
record_keys = |text| {
	bytes = text.to_utf8()
	var $keys = []
	var $depth = 0.I64
	var $quoted = Bool.False
	var $escaped = Bool.False
	var $expect_key = Bool.True
	var $capture = Bool.False
	var $start = 0.U64
	var $index = 0.U64
	for b in bytes {
		if $quoted {
			if $escaped {
				$escaped = Bool.False
			} else if b == '\\' {
				$escaped = Bool.True
			} else if b == '"' {
				$quoted = Bool.False
				if $capture {
					raw = Str.from_utf8(bytes.drop_first($start).take_first($index - $start + 1)).map_err(|_| OracleRecord)?
					key : Str
					key = Json.parse(raw).map_err(|_| OracleRecord)?
					$keys = $keys.append(key)
				}
			}
		} else if b == '"' {
			$quoted = Bool.True
			$capture = $depth == 1 and $expect_key
			$start = $index
		} else if b == '{' or b == '[' {
			$depth = $depth + 1
		} else if b == '}' or b == ']' {
			$depth = $depth - 1
		} else if b == ':' and $depth == 1 {
			$expect_key = Bool.False
		} else if b == ',' and $depth == 1 {
			$expect_key = Bool.True
		}
		$index = $index + 1
	}
	Ok($keys)
}

sample : OracleCases.Case
sample = { id: "0", operation: "forward", input: ["1970", "1", "1"], expected: ["ok", "0"], evidence: "control" }
expect OracleCases.load(Json.to_str(sample), 1, "gregorian") == Ok([sample])
expect OracleCases.compare(sample, "0\tok\t0\n") and !OracleCases.compare(sample, "0\tok\t1\n")
expect !OracleCases.compare(sample, "0\tok\t0\n0\tok\t0\n")
expect OracleCases.load("", 1, "gregorian") == Err(OracleRecord)
expect OracleCases.load("{\"id\":\"0\",\"id\":\"1\"}", 1, "gregorian") == Err(OracleRecord)
expect OracleCases.load("null", 1, "gregorian") == Err(OracleRecord)
expect OracleCases.load("${Json.to_str(sample)}\n${Json.to_str(sample)}\n", 2, "gregorian") == Err(OracleRecord)
expect OracleCases.validate({ ..sample, input: ["1970", "0", "0"], expected: ["error", "InvalidMonth"] }, "gregorian") == Ok({})
expect OracleCases.validate({ ..sample, input: ["9223372036854775808", "1", "1"] }, "gregorian") == Err(OracleRecord)
expect OracleCases.validate({ ..sample, input: ["1970", "256", "1"] }, "gregorian") == Err(OracleRecord)
expect OracleCases.validate({ ..sample, input: ["+1", "1", "1"] }, "gregorian") == Err(OracleRecord)
expect integer("-9223372036854775808") == Ok(-9223372036854775808)
expect integer("-0") == Err(OracleRecord)
expect record_keys("{\"id\":\"0\",\"i\\u0064\":\"1\",\"input\":[\"x,\\\"y\"],\"nested\":{\"ignored\":1}}") == Ok(["id", "id", "input", "nested"])
expect date_text("00010101", Bool.False)
expect ordered_values([10101.I64, 20240101]) == Ok({})

timed : OracleCases.Case
timed = { id: "0", operation: "rfc_timed", input: ["20240101T090000Z", "FREQ=HOURLY;COUNT=1", "-", "-", "20240101T000000Z", "20240102T000000Z"], expected: ["ok", "1704099600000000"], evidence: "control" }
expect OracleCases.validate(timed, "rfc_timed") == Ok({})
expect [["ok", "1", "1"], ["ok", "2", "1"], ["ok", "9223372036854775808"], ["ok", "1.5"], ["error"]].all(|expected| OracleCases.validate({ ..timed, expected }, "rfc_timed") == Err(OracleRecord))
expect OracleCases.validate({ ..timed, operation: "rfc_date" }, "rfc_timed") == Err(OracleRecord)
expect OracleCases.validate({ ..timed, input: ["20240101", "FREQ=HOURLY;COUNT=1", "-", "-", "20240101T000000Z", "20240102T000000Z"] }, "rfc_timed") == Err(OracleRecord)
expect OracleCases.validate({ ..timed, input: ["20240101T090000Z", "FREQ=HOURLY\n", "-", "-", "20240101T000000Z", "20240102T000000Z"] }, "rfc_timed") == Err(OracleRecord)
expect OracleCases.validate({ ..timed, input: ["20240101T090000Z", "FREQ=HOURLY;COUNT=1", "20240101T090000", "-", "20240101T000000Z", "20240102T000000Z"] }, "rfc_timed") == Err(OracleRecord)

expect OracleCases.validate({ id: "0", operation: "rfc_date", input: ["00010101", "FREQ=DAILY;COUNT=1", "-", "-", "00010101", "00010102"], expected: ["ok", "00010101"], evidence: "control" }, "rfc_date") == Ok({})
