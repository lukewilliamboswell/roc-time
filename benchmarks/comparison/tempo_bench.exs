defmodule ComparisonBench do
  def date_sum(v), do: Tempo.year(v) * 10000 + Tempo.month(v) * 100 + Tempo.day(v)
  def micros(v) do
    {:ok, d} = Tempo.to_date_time(v)
    DateTime.to_unix(d, :microsecond)
  end
  def day(v) do
    {:ok, d} = Tempo.to_date(v)
    Date.to_gregorian_days(d) - 719528
  end
  def run(data, size, n, op), do: loop(data, size, n, op, 0, 0)
  defp loop(_, _, n, _, n, sum), do: sum
  defp loop(data, size, n, op, i, sum), do: loop(data, size, n, op, i + 1, sum + op.(elem(data, rem(i, size))))
  def main([mode, ns, ws, ss | texts]) do
    [n, w, s] = Enum.map([ns, ws, ss], &String.to_integer/1)
    true = n in 1..10_000_000 and w in 0..10 and s in 0..50 and texts != []
    values = Enum.map(texts, &Tempo.parse_datetime!/1)
    dates = Enum.map(values, fn v -> Tempo.new!(year: Tempo.year(v), month: Tempo.month(v), day: Tempo.day(v)) end)
    if mode == "verify" do
      Enum.zip(values, dates) |> Enum.each(fn {v, d} -> IO.puts("#{day(d)}|#{micros(v)}") end)
    else
      day_step = Tempo.parse_duration!("P17D")
      {data, op} = case mode do
        "date_control" -> {dates, &date_sum/1}
        "date_to_day" -> {dates, fn v -> day(v) + 1000000 end}
        "construct" -> {Enum.map(dates, fn v -> [year: Tempo.year(v), month: Tempo.month(v), day: Tempo.day(v)] end), fn v -> date_sum(Tempo.new!(v)) end}
        "add_days" -> {dates, fn v -> date_sum(Tempo.shift(v, day_step)) end}
        "parse" -> {texts, fn v -> Integer.mod(micros(Tempo.parse_datetime!(v)), 1000000007) end}
        "resolve" -> {values, fn v -> Integer.mod(micros(v), 1000000007) end}
      end
      size = length(data)
      data = List.to_tuple(data)
      if w > 0, do: Enum.each(1..w, fn _ -> run(data, size, n, op) end)
      if s > 0 do
        Enum.each(1..s, fn _ ->
          start = System.monotonic_time(:nanosecond)
          checksum = run(data, size, n, op)
          elapsed = System.monotonic_time(:nanosecond) - start
          IO.puts("#{elapsed},#{checksum}")
        end)
      end
    end
  end
end
ComparisonBench.main(System.argv())
