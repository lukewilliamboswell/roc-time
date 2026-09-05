import DatabaseRecord
Zone013 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Africa/Monrovia", source_version: "2025b", source_digest: "58cf8955faf9d36560cb5f057ba880276c8c80e59bc30ba621087fca9e7778a3", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -2588.I32, minimum_offset: -2670.I32, maximum_offset: 0.I32, transitions: [{ second: -2776979812, offset: -2588 }, { second: -1604359012, offset: -2670 }, { second: 63593070, offset: 0 }] }
}
