import DatabaseRecord
Zone331 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Pago_Pago", source_version: "2025b", source_digest: "650d918751366590553063cd681592fdca8a09957e0ce2c18d6697ec385ef796", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 45432.I32, minimum_offset: -40968.I32, maximum_offset: 45432.I32, transitions: [{ second: -2445424632, offset: -40968 }, { second: -1861879032, offset: -39600 }] }
}
