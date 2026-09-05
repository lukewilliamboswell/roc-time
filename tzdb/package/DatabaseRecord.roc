DatabaseRecord :: [].{
 # Internal generated columns have identical lengths by construction. Full
 # provider verification compares every reconstructed transition checksum.
 expand : List(I64), List(I32) -> List({ second : I64, offset : I32 })
 expand = |times, offsets| List.map_with_index(times, |second, index| {
  offset = match List.get(offsets, index) {
   Ok(value) => value
   Err(_) => crash "Generated zone column lengths differ"
  }
  { second, offset }
 })
 Value : { schema : U16, axis : Str, requested_name : Str, canonical_name : Str, source_version : Str, source_digest : Str, profile : Str, future_handling : Str, start_second : I64, end_second : I64, initial_offset : I32, minimum_offset : I32, maximum_offset : I32, transitions : List({ second : I64, offset : I32 }) }
}
