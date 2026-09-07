import time.EnglishGregorian
import time.GregorianDate

## Group invoices by their supplied Gregorian accounting date, without a zone
## or clock. Equal dates remain separate invoices. Amounts are nonnegative USD
## cents; a group total outside U64 returns TotalOutOfRange.
## Parsing is linear in input text, grouping sorts O(n log n), and output is O(n).
InvoiceReport :: [].{
	Input : { id : Str, date : Str, cents : U64 }

	render = |invoices| {
		inputs : List(Input)
		inputs = invoices
		var $rows = []
		var $lines = ["Invoice report (USD; supplied accounting dates)"]
		for invoice in inputs {
			date = match GregorianDate.parse(invoice.date) {
				Ok(value) => value
				Err(error) => return Err(InvalidInvoiceDate(invoice.id, error))
			}
			week = GregorianDate.iso_week_date(date)
			$rows = $rows.append({ year: week.week_year, week: week.week, cents: invoice.cents })
			$lines = $lines.append("${invoice.id}: ${EnglishGregorian.date(date)} (${weekday_name(GregorianDate.weekday(date))}, day ${GregorianDate.ordinal_day(date).to_str()}) | ${week_label(week.week_year, week.week)} | USD ${money(invoice.cents)}")
		}
		$lines = $lines.append("Totals by ISO week (week year, not calendar year)")
		var $group = None
		for row in $rows.sort_with(
			|a, b| {
				if a.year < b.year or (a.year == b.year and a.week < b.week) {
					Before
				} else if a.year == b.year and a.week == b.week {
					Same
				} else {
					After
				}
			},
		) {
			match $group {
				None => {
					$group = Some(row)
				}
				Some(group) => {
					if group.year == row.year and group.week == row.week {
						total = match U128.to_u64_try(U64.to_u128(group.cents) + U64.to_u128(row.cents)) {
							Ok(value) => value
							Err(_) => return Err(TotalOutOfRange)
						}
						$group = Some({ ..group, cents: total })
					} else {
						$lines = $lines.append(total_line(group))
						$group = Some(row)
					}
				}
			}
		}
		match $group {
			Some(group) => {
				$lines = $lines.append(total_line(group))
			}
			None => {
				$lines = $lines.append("No invoices")
			}
		}
		Ok($lines)
	}
}

weekday_name = |day| match day {
	Monday => "Monday"
	Tuesday => "Tuesday"
	Wednesday => "Wednesday"
	Thursday => "Thursday"
	Friday => "Friday"
	Saturday => "Saturday"
	Sunday => "Sunday"
}

week_label = |year, week| "${year.to_str()}-W${two_digits(week.to_str())}"

money = |cents| "${U64.div_trunc_by(cents, 100).to_str()}.${two_digits(U64.rem_by(cents, 100).to_str())}"

two_digits = |text| if text.count_utf8_bytes() < 2 {
	"0${text}"
} else {
	text
}

total_line = |group| "${week_label(group.year, group.week)}: USD ${money(group.cents)}"
