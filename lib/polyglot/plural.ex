defmodule Polyglot.Plural do
  require Logger
  import Polyglot.Plural.Compiler

  def pluralise(lang, :range, arg) do
    do_plural(lang, :range, arg)
  end
  # TODO: strip currency/thousands separators?
  # Would need knowledge of different number formats based on lang.
  def pluralise(lang, kind, string_n) when is_bitstring(string_n) do
    n = cond do
      String.contains?(string_n, ".") ->
        {f, ""} = Float.parse(string_n)
        f
      String.contains?(string_n, ",") ->
        {f, ""} = string_n
                  |> String.replace(",", ".")
                  |> Float.parse
        f
      true ->
        {i, ""} = Integer.parse(string_n)
        i
    end
    do_plural(lang, kind, n, string_n)
  end
  def pluralise(lang, kind, n) do
    string_n = inspect(n)
    do_plural(lang, kind, n, string_n)
  end

  load_all
end
