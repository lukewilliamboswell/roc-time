import DatabaseRecord
Zone172 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Dhaka", source_version: "2025b", source_digest: "ac21a61306d6e2a91453641f4e3e732ebc9d542abc1d35a5d5db2a10340ebefa", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 21700.I32, minimum_offset: 19800.I32, maximum_offset: 25200.I32, transitions: [{ second: -2524543300, offset: 21200 }, { second: -891582800, offset: 23400 }, { second: -872058600, offset: 19800 }, { second: -862637400, offset: 23400 }, { second: -576138600, offset: 21600 }, { second: 1245430800, offset: 25200 }, { second: 1262278800, offset: 21600 }] }
}
