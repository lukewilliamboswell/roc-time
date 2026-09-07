import time.GregorianDate

ExportFixture := [].{
	date = |year, day| match GregorianDate.from_fields({ year, month: 1, day }) {
		Ok(value) => value
		Err(_) => crash "valid resource date"
	}
	months = |count| {
		var $values = []
		var $i = 0.U64
		while $i < count {
			# Two leading January entries keep a one-element retained slice valid.
			month = if $i < 2 {
				1.U8
			} else {
				U64.to_u8_wrap(U64.rem_by($i - 1, 12) + 1)
			}
			$values = $values.append(month)
			$i = $i + 1
		}
		$values
	}
}
