app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc1/roc-time-2T6KR7B59FhCSNghyPAgP2j61YiU1F537CkB6UFUwzfY.tar.zst",
}
import AnnotationExplanation

main! = |_| {
	reports = AnnotationExplanation.review("2022-07-08T00:14:07Z[Europe/Paris][u-ca=hebrew]")?
	echo!("Before interpretation (${Str.inspect(reports.source.status)})\n${reports.source.text}\n")
	echo!("Stored interpretation (${Str.inspect(reports.snapshot.status)})\n${reports.snapshot.text}\n")
	Ok({})
}
