defmodule Polyglot.Plural.Compiler do
  require Record
  Record.defrecordp :xmlAttribute, Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  Record.defrecordp :xmlText, Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl")

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
                          {ast, deps} = parse(rule)
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
    cardinals = load_plural_file(lang, '/plurals.xml')
                |> compile_plurals(lang, :cardinal)

    ordinals = load_plural_file(lang, '/ordinals.xml')
               |> compile_plurals(lang, :ordinal)

    ranges = load_range_file(lang, '/pluralRanges.xml')
             |> compile_ranges(lang)

    [cardinals, ordinals, ranges]
  end

  # Load a langs plurals from the XML
  defp load_plural_file(lang, file) do
    xml = xml_file(:code.priv_dir(:polyglot) ++ file)
    qs = "//pluralRules[contains(concat(' ', @locales, ' '), ' #{lang} ')]/pluralRule"
    for el <- q(qs, xml) do
      [xmlAttribute(value: count)] = q("./@count", el)
      [xmlText(value: rule)] = q("./text()", el)
      {List.to_string(count), extract_rule(rule)}
    end
  end
  defp load_range_file(lang, file) do
    xml = xml_file(:code.priv_dir(:polyglot) ++ file)
    qs = "//pluralRanges[contains(concat(' ', @locales, ' '), ' #{lang} ')]/pluralRange"
    for el <- q(qs, xml) do
      [xmlAttribute(value: result)] = q("./@result", el)
      [xmlAttribute(value: from)] = q("./@start", el)
      [xmlAttribute(value: to)] = q("./@end", el)
      {List.to_string(result), List.to_string(from), List.to_string(to)}
    end
  end
  defp xml_file(path) do
    {:ok, f} = :file.read_file(path)

    {xml, _} = f
               |> :binary.bin_to_list
               |> :xmerl_scan.string

    xml
  end
  defp q(s, xml) do
    :xmerl_xpath.string(to_char_list(s), xml)
  end
  defp extract_rule(rule) do
    Regex.run(~r/^[^@]*/, List.to_string(rule))
    |> List.first
    |> String.strip
  end

  # Parse a string into {ast, deps}
  defp parse("") do
    {true, HashSet.new}
  end
  defp parse(str) do
    {tokens, deps} = tokenise(str, [], HashSet.new)
    {parse_tree(tokens, [], []) |> compile, deps}
  end

  # Tokenise string, using simple recursive peeking
  defp tokenise(str, tokens, deps) do
    case str do
      "" -> {Enum.reverse(tokens), deps}

      <<"and", str::binary>> -> tokenise(str, [{:op,:and}|tokens], deps)
      <<"or", str::binary>> -> tokenise(str, [{:op,:or}|tokens], deps)
      <<"..", str::binary>> -> tokenise(str, [{:op,:range}|tokens], deps)
      <<"!=", str::binary>> -> tokenise(str, [{:op,:neq}|tokens], deps)
      <<"%", str::binary>> -> tokenise(str, [{:op,:mod}|tokens], deps)
      <<"=", str::binary>> -> tokenise(str, [{:op,:eq}|tokens], deps)
      <<",", str::binary>> -> tokenise(str, [{:op,:comma}|tokens], deps)

      <<" ", str::binary>> -> tokenise(str, tokens, deps)

      <<c::binary-size(1), str::binary>> when c == "n" or c == "i" or c == "f"
                                           or c == "t" or c == "v" or c == "w" ->
        v = Macro.var(String.to_atom(c), :plural)
        if c == "n" do
          tokenise(str, [{:var,v}|tokens], deps)
        else
          tokenise(str, [{:var,v}|tokens], Set.put(deps, v))
        end

      str ->
        case Regex.run(~r/^[0-9]+/, str) do
          [n] ->
            len = String.length(n)
            str = String.slice(str, len, String.length(str) - len)
            {i, ""} = Integer.parse(n)
            tokenise(str, [{:number, i}|tokens], deps)
          nil -> {:error, "Couldn't parse rule.", str}
        end
    end
  end

  # Parse tokens into a tree, using a shunting-yard parser
  @precedences %{or: 1,
                 and: 2,
                 neq: 3, eq: 3,
                 mod: 4,
                 comma: 5,
                 range: 6}

  defp parse_tree(tokens, opstack, output) do
    case {tokens, opstack, output} do
      {[], [], [result]} ->
        result
      {[], [op|opstack], output} ->
        push_op(op, [], opstack, output)
      {[{:op, o1}|rest], [], output} ->
        parse_tree(rest, [o1], output)
      {[{:op, o1}|rest]=tokens, [o2|opstack], output} ->
        if @precedences[o1] <= @precedences[o2] do
          push_op(o2, tokens, opstack, output)
        else
          parse_tree(rest, [o1,o2|opstack], output)
        end
      {[node|rest], opstack, output} ->
        parse_tree(rest, opstack, [node|output])
    end
  end

  defp push_op(op, tokens, opstack, [r,l|output]) do
    case {op, l} do
      {:comma, {:list, vs}} ->
        parse_tree(tokens, opstack, [{:list, [r|vs]}|output])
      {:comma, _} ->
        parse_tree(tokens, opstack, [{:list, [r,l]}|output])
      _ ->
        parse_tree(tokens, opstack, [{:binary, op, l, r}|output])
    end
  end

  # Compile out the tree into elixir forms
  @op_map %{or: :or,
            and: :and,
            neq: :!=, eq: :==,
            mod: :rem}

  defp compile(form) do
    case form do
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