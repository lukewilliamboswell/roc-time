import DatabaseRecord
Zone043 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "America/Bogota", source_version: "2025b", source_digest: "06a1fab8296bae54fe56c06691ed8c87e21f035475975874df50915122d2d67a", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -17776.I32, minimum_offset: -18000.I32, maximum_offset: -14400.I32, transitions: [{ second: -2707671824, offset: -17776 }, { second: -1739041424, offset: -18000 }, { second: 704869200, offset: -14400 }, { second: 729057600, offset: -18000 }] }
}
