import DatabaseRecord
Zone239 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Australia/Darwin", source_version: "2025b", source_digest: "6687b16e181d52557895e57e76106ee80c43564272e37c6b3dbf5443711009d2", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 31400.I32, minimum_offset: 31400.I32, maximum_offset: 37800.I32, transitions: [{ second: -2364108200, offset: 32400 }, { second: -2230189200, offset: 34200 }, { second: -1672558200, offset: 37800 }, { second: -1665387000, offset: 34200 }, { second: -883639800, offset: 37800 }, { second: -876123000, offset: 34200 }, { second: -860398200, offset: 37800 }, { second: -844673400, offset: 34200 }, { second: -828343800, offset: 37800 }, { second: -813223800, offset: 34200 }] }
}
