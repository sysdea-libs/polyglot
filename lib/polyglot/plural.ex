defmodule Polyglot.Plural do
  require Record
  require Logger
  Record.defrecordp :xmlAttribute, Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  Record.defrecordp :xmlText, Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl")

  defmacro __using__(_env) do
    quote do
      @before_compile Polyglot.Plural
      Module.register_attribute(__MODULE__, :plurals, accumulate: true)

      defp plural(lang, :range, arg) do
        plural_impl(lang, :range, arg)
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
        plural_impl(lang, kind, n, string_n)
      end
      defp plural(lang, kind, n) do
        string_n = inspect(n)
        plural_impl(lang, kind, n, string_n)
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
    {cardinals, ordinals, ranges} = load(lang)

    [cardinals
     |> compile_plurals(lang, :cardinal),

     ordinals
     |> compile_plurals(lang, :ordinal),

     compile_ranges(ranges, lang)]
  end

  defp compile_ranges(rules, lang) do
    clauses = for { result, from, to } <- rules do
      quote do
        { unquote(from), unquote(to) } -> unquote(result)
      end
    end

    quote do
      defp plural_impl(unquote(lang), :range, { from, to }) do
        from = plural(unquote(lang), :cardinal, from)
        to = plural(unquote(lang), :cardinal, to)
        case { from, to } do
          unquote(List.flatten clauses)
        end
      end
    end
  end

  # Compiles a list of rules into a def
  defp compile_plurals(rules, lang, kind) do
    { clauses, deps } = Enum.reduce(Enum.reverse(rules), { [], HashSet.new },
                          fn({name, rule}, { clauses, alldeps }) ->
                            {ast, deps} = parse(rule)
                            { [{:->, [], [[ast], name]}|clauses], Set.union(alldeps, deps) }
                          end)

    prelude = Set.delete(deps, :n)
              |> Enum.map(&quote(do: unquote(var(&1)) = unquote(compile_dep(&1))))

    ast = quote do
      defp plural_impl(unquote(lang), unquote(kind), unquote(var(:n)), unquote(var(:string_n))) do
        unquote_splicing(prelude)
        cond do
          unquote(clauses)
        end
      end
    end

    Logger.debug fn ->
      """
      Compiled plural:
      #{inspect(rules)}
        =>
      #{Macro.to_string(ast)}
      """
    end

    ast
  end

  # Helper function to generate var references
  defp var(name), do: {name, [], :plural}

  # Shared structure for v/f/t
  # TODO: see note on n_to_number on separators
  defp after_decimal do
    quote do: unquote(var(:string_n))
              |> String.split(~r/\.|,/)
              |> Enum.at(1) || ""
  end

  # Compiles the index numbers needed for pluralising
  defp compile_dep(:i) do
    quote do: trunc(unquote(var(:n)))
  end
  defp compile_dep(:v) do
    quote do: unquote(after_decimal) |> String.length
  end
  defp compile_dep(:f) do
    quote do: unquote(after_decimal) |> Integer.parse
  end
  defp compile_dep(:t) do
    quote do: unquote(after_decimal) |> String.strip(?0) |> String.length
  end

  defp load(lang) do
    { load_plural_file(lang, '/plurals.xml'),
      load_plural_file(lang, '/ordinals.xml'),
      load_range_file(lang, '/pluralRanges.xml') }
  end

  # Load a langs plurals from the XML
  defp load_plural_file(lang, file) do
    xml = xml_file(:code.priv_dir(:polyglot) ++ file)
    qs = "//pluralRules[contains(concat(' ', @locales, ' '), ' #{lang} ')]/pluralRule"
    for el <- q(qs, xml) do
      [xmlAttribute(value: count)] = q("./@count", el)
      [xmlText(value: rule)] = q("./text()", el)
      { List.to_string(count), extract_rule(rule) }
    end
  end
  defp load_range_file(lang, file) do
    xml = xml_file(:code.priv_dir(:polyglot) ++ file)
    qs = "//pluralRanges[contains(concat(' ', @locales, ' '), ' #{lang} ')]/pluralRange"
    for el <- q(qs, xml) do
      [xmlAttribute(value: result)] = q("./@result", el)
      [xmlAttribute(value: from)] = q("./@start", el)
      [xmlAttribute(value: to)] = q("./@end", el)
      { List.to_string(result), List.to_string(from), List.to_string(to) }
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
        atom = String.to_atom(c)
        tokenise(str, [{:var,atom}|tokens], Set.put(deps, atom))

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
  @precedences %{ or: 1,
                  and: 2,
                  neq: 3, eq: 3,
                  mod: 4,
                  comma: 5,
                  range: 6 }

  defp parse_tree([], [], [output]) do
    output
  end
  defp parse_tree([], [op|opstack], output) do
    push_op(op, [], opstack, output)
  end
  defp parse_tree([{:op, o1}|rest], [], output) do
    parse_tree(rest, [o1], output)
  end
  defp parse_tree([{:op, o1}|rest], [o2|opstack], output) do
    if @precedences[o1] <= @precedences[o2] do
      push_op(o2, [{:op, o1}|rest], opstack, output)
    else
      parse_tree(rest, [o1,o2|opstack], output)
    end
  end
  defp parse_tree([node|rest], opstack, output) do
    parse_tree(rest, opstack, [node|output])
  end

  defp push_op(:comma, tokens, opstack, [r,{:list, vs}|output]) do
    parse_tree(tokens, opstack, [{:list, [r|vs]}|output])
  end
  defp push_op(:comma, tokens, opstack, [r,l|output]) do
    parse_tree(tokens, opstack, [{:list, [r,l]}|output])
  end
  defp push_op(op, tokens, opstack, [r,l|output]) do
    parse_tree(tokens, opstack, [{:binary, op, l, r}|output])
  end

  # Compile out the tree into elixir forms
  @op_map %{ or: :or,
             and: :and,
             neq: :!=, eq: :==,
             mod: :rem }

  defp compile({:number, n}), do: n
  defp compile({:var, v}), do: var(v)
  defp compile({:binary, :eq, l, {:list, vs}}) do
    Enum.map(vs, &compile({:binary, :eq, l, &1}))
    |> Enum.reduce(&quote do: unquote(&2) or unquote(&1))
  end
  defp compile({:binary, :eq, l, {:binary, :range, lr, rr}}) do
    quote do
      unquote(compile(l)) in unquote(compile(lr))..unquote(compile(rr))
    end
  end
  defp compile({:binary, :neq, l, {:list, vs}}) do
    quote do: !unquote(compile({:binary, :eq, l, {:list, vs}}))
  end
  defp compile({:binary, op, l, r}) do
    {@op_map[op], [context: Elixir, import: Kernel], [compile(l), compile(r)]}
  end
end
