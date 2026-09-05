import DatabaseRecord
Zone150 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Antarctica/Vostok", source_version: "2025b", source_digest: "703a7e078c0a5c4f14e5bff3a89225c5d198f802003024c93991b76d164128d7", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 0.I32, minimum_offset: 0.I32, maximum_offset: 25200.I32, transitions: [{ second: -380073600, offset: 25200 }, { second: 760035600, offset: 0 }, { second: 783648000, offset: 25200 }, { second: 1702839600, offset: 18000 }] }
}
