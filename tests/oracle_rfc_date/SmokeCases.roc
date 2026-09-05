SmokeCases :: [].{
 inputs : List({ input : List(Str), expected : Str })
 inputs = [
{ input: ["20240101", "until=20240103;freq=daily;interval=3;wkst=we", "-", "20240101,20240101", "20231201", "20260101"], expected: "ok" },
{ input: ["20240101", "wkst=tu;interval=2;until=20240107;byday=mo,fr;freq=weekly", "-", "20240101,20240101", "20231201", "20260101"], expected: "ok" },
{ input: ["20240131", "interval=3;wkst=fr;until=20240417;freq=monthly", "-", "20240131,20240131", "20231201", "20260101"], expected: "ok" },
{ input: ["20240101", "wkst=fr;interval=3;bysetpos=1,-1;freq=monthly;until=20240202;byday=mo", "-", "20240101,20240101", "20231201", "20260101"], expected: "ok\t20240129" },
{ input: ["20240229", "interval=2;freq=yearly;until=20240528;wkst=th;bymonthday=29;bymonth=2", "-", "20240229,20240229", "20231201", "20260101"], expected: "ok" },
{ input: ["20240101", "bysetpos=1,-1;interval=1;byday=mo;until=20240314;freq=yearly;wkst=mo", "-", "20240101,20240101", "20231201", "20260101"], expected: "ok" },
{ input: ["20240101", "bymonth=1;byday=1mo;interval=3;until=20240104;freq=yearly;wkst=th", "-", "20240101,20240101", "20231201", "20260101"], expected: "ok" },
{ input: ["20240101", "wkst=fr;freq=yearly;bymonth=1,6;byday=1mo;until=20240606;interval=1", "-", "20240101,20240101", "20231201", "20260101"], expected: "ok\t20240603" }
]
}
