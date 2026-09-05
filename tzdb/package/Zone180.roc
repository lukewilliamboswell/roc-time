import DatabaseRecord
Zone180 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Ho_Chi_Minh", source_version: "2025b", source_digest: "47e45e54cade31c1131b44a27e37dee73f8f810a54b0a8d3e9d55b10acd3dec1", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 25590.I32, minimum_offset: 25200.I32, maximum_offset: 32400.I32, transitions: [{ second: -2004073590, offset: 25590 }, { second: -1851577590, offset: 25200 }, { second: -852105600, offset: 28800 }, { second: -782643600, offset: 32400 }, { second: -767869200, offset: 25200 }, { second: -718095600, offset: 28800 }, { second: -457772400, offset: 25200 }, { second: -315648000, offset: 28800 }, { second: 171820800, offset: 25200 }] }
}
