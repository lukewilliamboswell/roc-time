app [main!] {
	time: "../../package/main.roc",
}
import CatalogueStorage

main! = |_| {
	restored = CatalogueStorage.save_and_restore("1984?", "2026-06-15T10:30:00.120+00:00")?
	echo!("Restored archive description: ${restored.date}\n")
	echo!("Restored recording declaration: ${restored.timestamp}\n")
	Ok({})
}
