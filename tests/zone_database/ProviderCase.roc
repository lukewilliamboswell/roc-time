import zones.Database
import time.ZoneRules
import time.PosixBoundary
import time.FixedOffset

ProviderCase :: [].{
	verify = |unknown| {
		alias = Database.get("Australia/Victoria")?
		if alias.requested_name != "Australia/Victoria" or alias.canonical_name != "Australia/Melbourne" {
			return Err(WrongAlias)
		}
		match Database.get(unknown) {
			Err(UnknownZone(name)) => {
				if name != unknown {
					return Err(WrongUnknownName)
				}
			}
			_ => return Err(MissingUnknownZoneError)
		}
		rules = ZoneRules.from_database(alias)?
		outside = PosixBoundary.from_microseconds(alias.end_second * 1000000)
		match ZoneRules.offset_at(rules, outside) {
			Err(OutsideValidity) => {}
			_ => return Err(MissingHorizonError)
		}
		# 2050-01-01 is beyond Melbourne's final explicit TZif transition.
		future = PosixBoundary.from_microseconds(2524608000000000)
		offset = ZoneRules.offset_at(rules, future)?
		if FixedOffset.to_seconds(offset) != 39600 {
			return Err(WrongFutureOffset)
		}
		Ok({})
	}
}
