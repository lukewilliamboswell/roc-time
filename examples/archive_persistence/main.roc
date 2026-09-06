app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc1/roc-time-2T6KR7B59FhCSNghyPAgP2j61YiU1F537CkB6UFUwzfY.tar.zst",
}
import ArchivePersistence

main! = |_| {
	restored = ArchivePersistence.save_and_restore("1984?", "2026-06-15T10:30:00.120+00:00")?
	echo!("Restored archive description: ${restored.date}\n")
	echo!("Restored recording declaration: ${restored.timestamp}\n")
	echo!("Stored boundary microseconds: ${restored.coordinate}\n")
	diary = ArchivePersistence.historical(Julian, { year: 1900, month: 2, day: 29 }, 12, 30, [{ scope: Day, qualifier: Uncertain }])?
	echo!("Restored diary date: ${diary.date}\n")
	echo!("Restored diary resolution: ${diary.resolution}\n")
	echo!("Restored diary qualifiers: ${diary.qualifications}\n")
	Ok({})
}
