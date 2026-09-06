app [main!] {
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc1/roc-time-2T6KR7B59FhCSNghyPAgP2j61YiU1F537CkB6UFUwzfY.tar.zst",
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
