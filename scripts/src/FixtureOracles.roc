import JsonShape

## Existing authored fixture protocols. There is no calendar computation here:
## expected fields come from pinned independent JSONL, never the library.
FixtureOracles := [].{
	DateOutput : { parts : { start : Str, rule : Str, inclusions : List(Str), exclusions : List(Str) }, dates : List(Str) }
	CapOutput : { bytes : U64, start : Str, rule : Str, inclusions : U64, exclusions : U64 }
	TimedOutput : { parts : { start : Str, rule : Str, mode : Str, duration : Str, inclusions : List(Str), exclusions : List(Str), periods : List(Str) }, occurrences : List({ source : Str, start : I64, end : I64 }) }
	TimedCapOutput : { bytes : U64, exclusions : U64 }
	Expected : [Civil(List(I64)), Date(DateOutput), Cap(CapOutput), Timed(TimedOutput), TimedCap(TimedCapOutput), Error(Str)]
	Case : { input : List(Str), label : Str, expected : Expected }
	load : Str, Str -> Try(List(Case), [FixtureRecord])
	load = |kind, source| {
		if source.count_utf8_bytes() > 1048576 {
			return Err(FixtureRecord)
		}
		lines = source.drop_suffix("\n").split_on("\n")
		if lines.is_empty() or lines.len() > 4096 {
			return Err(FixtureRecord)
		}
		lines.map_try(
			|line| {
				if line.count_utf8_bytes() > 131072 {
					return Err(FixtureRecord)
				}
				match kind {
					"civil" => {
						row : { input : Str, origin : Str, reference_year : I64, expected : List(I64) }
						row = Json.parse(line).map_err(|_| FixtureRecord)?
						if !["direct-python", "cycle-extension"].contains(row.origin) or row.expected.len() != 5 or JsonShape.keys(line) != JsonShape.keys(Json.to_str(row)) {
							return Err(FixtureRecord)
						}
						Ok({ input: [row.input], label: row.input, expected: Civil(row.expected) })
					}
					"date" => {
						header : { input : Str, error : Try(Str, [Missing]) }
						header = Json.parse(line).map_err(|_| FixtureRecord)?
						match header.error {
							Ok(error) => {
								if JsonShape.keys(line) != 2 {
									return Err(FixtureRecord)
								}
								Ok({ input: [header.input], label: header.input, expected: Error(error) })
							}
							Err(Missing) if header.input == "exact-cap" => {
								row : { input : Str, expected : CapOutput }
								row = Json.parse(line).map_err(|_| FixtureRecord)?
								if JsonShape.keys(line) != JsonShape.keys(Json.to_str(row)) {
									return Err(FixtureRecord)
								}
								Ok({ input: [row.input], label: row.input, expected: Cap(row.expected) })
							}
							Err(Missing) => {
								row : { input : Str, expected : DateOutput }
								row = Json.parse(line).map_err(|_| FixtureRecord)?
								if JsonShape.keys(line) != JsonShape.keys(Json.to_str(row)) {
									return Err(FixtureRecord)
								}
								Ok({ input: [row.input], label: row.input, expected: Date(row.expected) })
							}
						}
					}
					"timed" => {
						header : { name : Str, input : List(Str), error : Try(Str, [Missing]) }
						header = Json.parse(line).map_err(|_| FixtureRecord)?
						if header.input.is_empty() or header.input.len() > 32 {
							return Err(FixtureRecord)
						}
						match header.error {
							Ok(error) => {
								if JsonShape.keys(line) != 3 {
									return Err(FixtureRecord)
								}
								Ok({ input: header.input, label: header.name, expected: Error(error) })
							}
							Err(Missing) if header.name == "native-exact-cap" => {
								row : { name : Str, input : List(Str), expected : TimedCapOutput }
								row = Json.parse(line).map_err(|_| FixtureRecord)?
								if JsonShape.keys(line) != JsonShape.keys(Json.to_str(row)) {
									return Err(FixtureRecord)
								}
								Ok({ input: row.input, label: row.name, expected: TimedCap(row.expected) })
							}
							Err(Missing) => {
								row : { name : Str, input : List(Str), expected : TimedOutput }
								row = Json.parse(line).map_err(|_| FixtureRecord)?
								if JsonShape.keys(line) != JsonShape.keys(Json.to_str(row)) {
									return Err(FixtureRecord)
								}
								Ok({ input: row.input, label: row.name, expected: Timed(row.expected) })
							}
						}
					}
					_ => Err(FixtureRecord)
				}
			},
		)
	}
	compare : Expected, Str -> Bool
	compare = |expected, output| match expected {
		Civil(values) => match output.trim().split_on(",").map_try(I64.from_str) {
			Ok(observed) => observed.len() == 5 and observed == values
			Err(_) => Bool.False
		}
		Error(error) => output.trim() == error
		Date(value) => same_output(value, output)
		Cap(value) => same_output(value, output)
		Timed(value) => same_output(value, output)
		TimedCap(value) => same_output(value, output)
	}
}

same_output = |expected, output| match Json.parse(output) {
	Ok(actual) => actual == expected and JsonShape.keys(output) == JsonShape.keys(Json.to_str(expected))
	Err(_) => Bool.False
}
expect FixtureOracles.compare(Civil([6, 1, 1999, 52, 6]), "6,1,1999,52,6\n")
expect ["", "null", "6,1,1999,52", "6,1,1999,52,6,7", "6,1,1999,52,x", "6,1,1999,53,6"].all(|wrong| !FixtureOracles.compare(Civil([6, 1, 1999, 52, 6]), wrong))
expect !FixtureOracles.compare(Error("OutOfRange(\"count\")"), "OutOfRange(\"wrong-field\")")

empty_date : FixtureOracles.DateOutput
empty_date = { parts: { start: "20250101", rule: "FREQ=DAILY;COUNT=1", inclusions: [], exclusions: [] }, dates: [] }
expect FixtureOracles.compare(Date(empty_date), "{\"dates\":[],\"parts\":{\"exclusions\":[],\"rule\":\"FREQ=DAILY;COUNT=1\",\"start\":\"20250101\",\"inclusions\":[]}}")
expect !FixtureOracles.compare(Date(empty_date), "{\"unknown\":[],\"parts\":{\"exclusions\":[],\"rule\":\"FREQ=DAILY;COUNT=1\",\"start\":\"20250101\",\"inclusions\":[]}}")
expect !FixtureOracles.compare(Date(empty_date), "{\"dates\":[],\"extra\":0,\"parts\":{\"exclusions\":[],\"rule\":\"FREQ=DAILY;COUNT=1\",\"start\":\"20250101\",\"inclusions\":[]}}")
expect !FixtureOracles.compare(Date(empty_date), "{\"dates\":[],\"dates\":[],\"parts\":{\"exclusions\":[],\"rule\":\"FREQ=DAILY;COUNT=1\",\"start\":\"20250101\",\"inclusions\":[]}}")
expect ["", "null", "{}", "[]", "{broken"].all(|output| !FixtureOracles.compare(Date(empty_date), output))
boundary_timed : FixtureOracles.TimedOutput
boundary_timed = { parts: { start: "19700101T000000Z", rule: "FREQ=DAILY;COUNT=1", mode: "Utc", duration: "PT1S", inclusions: [], exclusions: [], periods: [] }, occurrences: [{ source: "1970-01-01T00:00:00", start: -9223372036854775808, end: 9223372036854775807 }] }
expect FixtureOracles.compare(Timed(boundary_timed), "{\"parts\":{\"start\":\"19700101T000000Z\",\"rule\":\"FREQ=DAILY;COUNT=1\",\"mode\":\"Utc\",\"duration\":\"PT1S\",\"inclusions\":[],\"exclusions\":[],\"periods\":[]},\"occurrences\":[{\"source\":\"1970-01-01T00:00:00\",\"start\":-9223372036854775808,\"end\":9223372036854775807}]}")
expect !FixtureOracles.compare(Timed(boundary_timed), "{\"parts\":{\"start\":\"19700101T000000Z\",\"rule\":\"FREQ=DAILY;COUNT=1\",\"mode\":\"Utc\",\"duration\":\"PT1S\",\"inclusions\":[],\"exclusions\":[],\"periods\":[]},\"occurrences\":[{\"source\":\"1970-01-01T00:00:00\",\"start\":-9223372036854775808,\"end\":9223372036854775806}]}")
