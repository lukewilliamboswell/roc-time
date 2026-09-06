app [main!] {
	time: "../../package/main.roc",
}
import AnnotationExplanation

main! = |_| {
	reports = AnnotationExplanation.review("2022-07-08T00:14:07Z[Europe/Paris][u-ca=hebrew]")?
	echo!("Before interpretation (${Str.inspect(reports.source.status)})\n${reports.source.text}\n")
	echo!("Stored interpretation (${Str.inspect(reports.snapshot.status)})\n${reports.snapshot.text}\n")
	Ok({})
}
