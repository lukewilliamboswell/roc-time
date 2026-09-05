import DatabaseRecord
Zone219 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Tokyo", source_version: "2025b", source_digest: "59a3871430f0d3b93e619fa30a43a41d1e88bdd49ff26f09d0f405a500706f96", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 33539.I32, minimum_offset: 32400.I32, maximum_offset: 36000.I32, transitions: [{ second: -2587712400, offset: 32400 }, { second: -683802000, offset: 36000 }, { second: -672310800, offset: 32400 }, { second: -654771600, offset: 36000 }, { second: -640861200, offset: 32400 }, { second: -620298000, offset: 36000 }, { second: -609411600, offset: 32400 }, { second: -588848400, offset: 36000 }, { second: -577962000, offset: 32400 }] }
}
