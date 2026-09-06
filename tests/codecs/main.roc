app [main!] {
	time: "../../package/main.roc",
}
import CodecChecks
main! = |_| {
	CodecChecks.run({
		source: "{\"date\":\"1984?\",\"dates\":[\"2020-02-29\",\"2022-06~\"],\"exact\":\"2026-06-15T09:00:00Z/2026-06-15T10:00:00Z\",\"ixdtf\":\"2022-07-08T00:14:07Z[Europe/Paris][u-ca=hebrew]\",\"rfc_date\":\"19970902T090000Z\",\"rfc_duration\":\"PT1H\",\"rfc_period\":\"19970902T090000Z/PT1H\",\"stamp\":\"2026-06-15T10:30:00.120-00:00\",\"tail\":\"kept\"}",
		canonical: "{\"date\":\"1984?\",\"dates\":[\"2020-02-29\",\"2022-06~\"],\"exact\":\"2026-06-15T09:00:00Z/2026-06-15T10:00:00Z\",\"ixdtf\":\"2022-07-08T00:14:07Z[Europe/Paris][u-ca=hebrew]\",\"rfc_date\":\"19970902T090000Z\",\"rfc_duration\":\"PT3600S\",\"rfc_period\":\"19970902T090000Z/PT3600S\",\"stamp\":\"2026-06-15T10:30:00.120Z\",\"tail\":\"kept\"}",
		invalid_date: "\"2020-02-30\"",
		invalid_stamp: "\"2020-02-30T00:00:00Z\"",
		invalid_exact: "\"2026-06-15T09:00:00Z/2026-06-15T09:00:00Z\"",
		invalid_ixdtf: "\"2022-07-08T00:14:07Z[!knort=value]\"",
		invalid_rfc_date: "\"20200230T000000Z\"",
		invalid_duration: "\"PT0S\"",
		invalid_period: "\"19970902T090000Z/19970902T090000Z\"",
		syntax: "{broken",
		backing: "{\"value\":\"1984?\"}",
		nested_bad: "{\"dates\":[\"1984?\",\"2020-02-30\"],\"tail\":\"kept\"}",
		tokens: ["1984?", "2020-02-29", "tail"],
		year: "2020",
	})
	echo!("PASS semantic codecs\n")
	Ok({})
}
