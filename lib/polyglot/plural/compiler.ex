defmodule Polyglot.Plural.Compiler do
  alias Polyglot.Plural.Parser
  alias Polyglot.Plural.Loader

  defmacro load_all do
    cardinals = for {locales, rules} <- Loader.load_all_plurals('/plurals.xml') do
      compile_plurals(rules, locales, :cardinal)
    end

    ordinals = for {locales, rules} <- Loader.load_all_plurals('/ordinals.xml') do
      compile_plurals(rules, locales, :ordinal)
    end

    ranges = for {locales, rules} <- Loader.load_all_ranges('/pluralRanges.xml') do
      compile_ranges(rules, locales)
    end

    [cardinals, ordinals, ranges]
  end

  def compile_ranges(rules, locales) do
    clauses = for {result, from, to} <- rules do
      quote do
        {unquote(from), unquote(to)} -> unquote(result)
      end
    end

    langs = locales
            |> to_string
            |> String.split(" ")

    quote do
      defp do_plural(lang, :range, {from, to}) when lang in unquote(langs) do
        from = pluralise(lang, :cardinal, from)
        to = pluralise(lang, :cardinal, to)
        case {from, to} do
          unquote(List.flatten clauses)
        end
      end
    end
  end

  # Compiles a list of rules into a def
  def compile_plurals(rules, locales, kind) do
    {clauses, deps} = Enum.map_reduce rules, HashSet.new,
                        fn({name, rule}, alldeps) ->
                          {tree, deps} = Parser.parse(rule)
                          ast = compile(tree)
                          {{:->, [], [[ast], name]}, Set.union(alldeps, deps)}
                        end

    n = Macro.var(:n, :plural)
    string_n = Macro.var(:string_n, :plural)

    prelude = for v <- deps do
                {:=, [], [v, compile_dep(v, n, string_n)]}
              end

    langs = locales
            |> to_string
            |> String.split(" ")

    quote do
      defp do_plural(lang, unquote(kind), unquote(n), unquote(string_n)) when lang in unquote(langs) do
        unquote_splicing(prelude)
        cond do
          unquote(clauses)
        end
      end
    end
  end

  # Shared structure for v/f/t
  # TODO: handle currency/thousands separators?
  defp after_decimal(string_n) do
    quote do: unquote(string_n)
              |> String.split(~r/\.|,/)
              |> Enum.at(1) || ""
  end

  # Compiles the index numbers needed for pluralising
  defp compile_dep({v, _, _}, n, string_n) do
    case v do
      :i -> quote do: trunc(unquote(n))
      :v -> quote do: unquote(after_decimal string_n) |> String.length
      :f -> quote do: unquote(after_decimal string_n) |> Integer.parse
      :t -> quote do: unquote(after_decimal string_n) |> String.strip(?0) |> String.length
    end
  end

  # Compile out the tree into elixir forms
  @op_map %{or: :or,
            and: :and,
            neq: :!=, eq: :==,
            mod: :rem}

  defp compile(form) do
    case form do
      true -> true
      {:number, n} -> n
      {:var, v} -> v
      {:binary, :eq, l, {:list, vs}} ->
        compiled = for v <- vs, do: compile({:binary, :eq, l, v})

        compiled
        |> Enum.reduce(&quote do: unquote(&2) or unquote(&1))
      {:binary, :eq, l, {:binary, :range, lr, rr}} ->
        quote do: unquote(compile(l)) in unquote(compile(lr))..unquote(compile(rr))
      {:binary, :neq, _, {:list, _}}=form ->
        quote do: !unquote(compile(put_elem(form, 1, :eq)))
      {:binary, op, l, r} ->
        {@op_map[op], [context: Elixir, import: Kernel], [compile(l), compile(r)]}
    end
  end
end
