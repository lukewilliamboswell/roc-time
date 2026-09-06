app [main!] {
	time: "../../package/main.roc",
}
import ArchivePersistence

main! = |_| {
	restored = ArchivePersistence.save_and_restore("1984?", "2026-06-15T10:30:00.120+00:00")?
	echo!("Restored archive description: ${restored.date}\n")
	echo!("Restored recording declaration: ${restored.timestamp}\n")
	echo!("Stored boundary microseconds: ${restored.coordinate}\n")
	Ok({})
}
