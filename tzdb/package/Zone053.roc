import DatabaseRecord
Zone053 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "America/Costa_Rica", source_version: "2025b", source_digest: "8a1a2a03fb479989b46234d12d9bb7abc3eab2aa8e79bd4210b8d684f7ff1d71", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -20173.I32, minimum_offset: -21600.I32, maximum_offset: -18000.I32, transitions: [{ second: -2524501427, offset: -20173 }, { second: -1545071027, offset: -21600 }, { second: 288770400, offset: -18000 }, { second: 297234000, offset: -21600 }, { second: 320220000, offset: -18000 }, { second: 328683600, offset: -21600 }, { second: 664264800, offset: -18000 }, { second: 678344400, offset: -21600 }, { second: 695714400, offset: -18000 }, { second: 700635600, offset: -21600 }] }
}
