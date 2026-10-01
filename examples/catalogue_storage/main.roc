app [main!] {
	roc: "nightly-2026-09-27-a3ce7f1",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-GPETAiR4TeEPxDA1F6qHxbDnFexmj4tYgUrkEryBhtdP.tar.zst",
}
import CatalogueStorage

main! = |_| {
	restored = CatalogueStorage.save_and_restore("1984?", "2026-06-15T10:30:00.120+00:00")?
	echo!("Restored archive description: ${restored.date}\n")
	echo!("Restored recording declaration: ${restored.timestamp}\n")
	Ok({})
}
