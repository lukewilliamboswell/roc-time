import DatabaseRecord
Zone001 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Africa/Nairobi", source_version: "2025b", source_digest: "0783854f52c33ada6b6d2a5d867662f0ae8e15238d2fce7b9ada4f4d319eb466", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 8836.I32, minimum_offset: 8836.I32, maximum_offset: 10800.I32, transitions: [{ second: -1946168836, offset: 9000 }, { second: -1309746600, offset: 10800 }, { second: -1261969200, offset: 9000 }, { second: -1041388200, offset: 9900 }, { second: -865305900, offset: 10800 }] }
}
