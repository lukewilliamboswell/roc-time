import DatabaseRecord
Zone171 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Colombo", source_version: "2025b", source_digest: "400ca32bb82d5d459f2ee8eed4cd07dff7b0ea24ccf9bc1fccee686e0bda1f2f", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 19164.I32, minimum_offset: 19164.I32, maximum_offset: 23400.I32, transitions: [{ second: -2840159964, offset: 19172 }, { second: -2019705572, offset: 19800 }, { second: -883287000, offset: 21600 }, { second: -862639200, offset: 23400 }, { second: -764051400, offset: 19800 }, { second: 832962600, offset: 23400 }, { second: 846266400, offset: 21600 }, { second: 1145039400, offset: 19800 }] }
}
