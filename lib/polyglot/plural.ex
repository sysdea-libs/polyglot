defmodule Polyglot.Plural do
  require Logger
  require Polyglot.Plural.Compiler, as: Compiler

  defmacro __using__(_env) do
    quote do
      @before_compile Polyglot.Plural
      Module.register_attribute(__MODULE__, :plurals, accumulate: true)

      defp plural(lang, :range, arg) do
        do_plural(lang, :range, arg)
      end
      # TODO: strip currency/thousands separators?
      # Would need knowledge of different number formats based on lang.
      defp plural(lang, kind, string_n) when is_bitstring(string_n) do
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
      defp plural(lang, kind, n) do
        string_n = inspect(n)
        do_plural(lang, kind, n, string_n)
      end
    end
  end

  defmacro __before_compile__(env) do
    plurals = Module.get_attribute(env.module, :plurals)

    if is_bitstring(plurals) do
      compile_lang(plurals)
    else
      plurals
      |> Enum.into(HashSet.new)
      |> Enum.map(&compile_lang(&1))
      |> List.flatten
    end
  end

  defp compile_lang(lang) do
    {cardinals, ordinals, ranges} = Compiler.load(lang)

    Logger.debug "Compiling plural(#{inspect lang}, kind, n)"

    [Compiler.compile_plurals(cardinals, lang, :cardinal),
     Compiler.compile_plurals(ordinals, lang, :ordinal),
     Compiler.compile_ranges(ranges, lang)]
  end

end
