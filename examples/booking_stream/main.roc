app [main!] {
	time: "../../package/main.roc",
}
import BookingStream
import time.Coverage

main! = |args| {
	inputs = [
		Ok("2026-06-15T09:00:00Z/2026-06-15T10:00:00Z"),
		Ok("2026-06-15T11:00:00Z/2026-06-15T12:00:00Z"),
		if (args.contains("--fail-source")) Err(SourceUnavailable) else Ok("2026-06-15T12:00:00Z/2026-06-15T13:00:00Z"),
	].iter().stream()
	first = BookingStream.consume!({ builder: Coverage.SortedBuilder.empty, source: inputs, pending: Ready }, 1)?
	match first {
		Completed(_) => Err(ExpectedPause)
		Paused(progress) => {
			echo!("Paused at one member\n")
			match BookingStream.consume!(progress, 2)? {
				Completed(coverage) => {
					echo!("Imported ${coverage.member_count().to_str()} occupied windows\n")
					Ok({})
				}
				Paused(_) => Err(UnexpectedPause)
			}
		}
	}
}
