## Application-owned clock policy for a fictional research voyage.
## This is a ship schedule, not an IANA zone or a prediction of civil law.
ShipClock :: [].{
	Release : [Published, Revised]

	## Same structural data boundary as the optional zone database; no core import.
	get = |name, release| {
		if name != "Voyage/Research" {
			return Err(UnknownZone(name))
		}
		# The captain postpones the planned clock advance by one day.
		change = match release {
			Published => { version: "itinerary-1", second: 1782864000.I64 }
			Revised => { version: "itinerary-2", second: 1782950400.I64 }
		}
		Ok({
			schema: 1.U16,
			axis: "posix-seconds-1970",
			requested_name: name,
			canonical_name: name,
			source_version: change.version,
			# Application source identity, not a cryptographic authenticity claim.
			source_digest: "ship-clock/${change.version}",
			profile: "research-voyage-2026",
			future_handling: "expanded-through-validity",
			# Valid from 2026-01-01T00:00Z to 2027-01-01T00:00Z, exclusive.
			start_second: 1767225600.I64,
			end_second: 1798761600.I64,
			initial_offset: 0.I32,
			# The ship's policy permits only UTC and UTC+01, including outside
			# this loaded year. These are global guarantees, not sampled bounds.
			minimum_offset: 0.I32,
			maximum_offset: 3600.I32,
			transitions: [{ second: change.second, offset: 3600.I32 }],
		})
	}
}
