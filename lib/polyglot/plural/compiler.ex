defmodule Polyglot.Plural.Compiler do
  alias Polyglot.Plural.Parser
  alias Polyglot.Plural.Loader

  def compile_ranges(rules, lang) do
    clauses = for {result, from, to} <- rules do
      quote do
        {unquote(from), unquote(to)} -> unquote(result)
      end
    end

    quote do
      defp do_plural(unquote(lang), :range, {from, to}) do
        from = pluralise(unquote(lang), :cardinal, from)
        to = pluralise(unquote(lang), :cardinal, to)
        case {from, to} do
          unquote(List.flatten clauses)
        end
      end
    end
  end

  # Compiles a list of rules into a def
  def compile_plurals(rules, lang, kind) do
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

    quote do
      defp do_plural(unquote(lang), unquote(kind), unquote(n), unquote(string_n)) do
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

  defmacro load(lang) do
    cardinals = Loader.load_plural_rules(lang, '/plurals.xml')
                |> compile_plurals(lang, :cardinal)

    ordinals = Loader.load_plural_rules(lang, '/ordinals.xml')
               |> compile_plurals(lang, :ordinal)

    ranges = Loader.load_range_rules(lang, '/pluralRanges.xml')
             |> compile_ranges(lang)

    [cardinals, ordinals, ranges]
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
        for v <- vs, do: compile({:binary, :eq, l, v})
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
