app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0/roc-time-6gt2mALoAXMVKcQvCpdisfaAU3S9XVdV3vR2CNA7e43t.tar.zst",
}
import CatalogueStorage

main! = |_| {
	restored = CatalogueStorage.save_and_restore("1984?", "2026-06-15T10:30:00.120+00:00")?
	echo!("Restored archive description: ${restored.date}\n")
	echo!("Restored recording declaration: ${restored.timestamp}\n")
	Ok({})
}
