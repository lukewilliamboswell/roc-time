app [main!] {
	roc: "nightly-2026-09-27-a3ce7f1",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-GPETAiR4TeEPxDA1F6qHxbDnFexmj4tYgUrkEryBhtdP.tar.zst",
}
import AnnotationExplanation

main! = |_| {
	reports = AnnotationExplanation.review("2022-07-08T00:14:07Z[Europe/Paris][u-ca=hebrew]")?
	echo!("Before interpretation (${Str.inspect(reports.source.status)})\n${reports.source.text}\n")
	echo!("Stored interpretation (${Str.inspect(reports.snapshot.status)})\n${reports.snapshot.text}\n")
	Ok({})
}
