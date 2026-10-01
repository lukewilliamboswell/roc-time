app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.2/9weENCAXVZV14WFpwHqP3rpn46EDJWQQknSLpa1Hg5nL.tar.zst",
	time: "../../package/main.roc",
}

import fuzz.Fuzz
import CalendarCase

target = Fuzz.target({ name: "calendars-v1", test: CalendarCase.check, show: |input| Str.inspect(input) })
