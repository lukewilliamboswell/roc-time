app [main!] {
	time: "../../package/main.roc",
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
