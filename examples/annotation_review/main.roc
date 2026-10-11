app [main!] {
	roc: "nightly-2026-09-27-a3ce7f1",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-GPETAiR4TeEPxDA1F6qHxbDnFexmj4tYgUrkEryBhtdP.tar.zst",
}
import AnnotationReview

main! = |_args| {
	lines = AnnotationReview.review([
		"2022-07-08T00:14:07Z[Europe/Paris]",
		"2022-07-08T00:14:07+00:00[Europe/Paris]",
		"2022-07-08T00:14:07Z[Europe/Paris][u-ca=hebrew]",
	])?
	echo!("Review imported timestamp annotations\n")
	for line in lines {
		echo!("${line}\n")
	}
	Ok({})
}
