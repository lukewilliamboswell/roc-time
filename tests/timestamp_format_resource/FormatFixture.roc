import time.OffsetTimestamp

# Independent canonical spellings: every supported decimal width, zero-valued
# fractions, nonzero fractions, UTC assertion distinctions and date-only bounds.
FormatFixture := [].{
	make = |year| {
		fractions = ["", ".0", ".00", ".003", ".0040", ".00050", ".000006"]
		var texts = []
		for fraction in fractions {
			for offset in ["Z", "+00:00", "-12:45"] {
				texts = texts.append("${year}-01-02T03:04:05${fraction}${offset}")
			}
		}
		values = texts.map(
			|text| match OffsetTimestamp.parse(text) {
				Ok(v) => v
				Err(_) => crash "validated formatter corpus"
			},
		)
		{ texts, values }
	}
}
