defmodule Polyglot.Compiler do
  require Logger

  def compile_string!(lang, key, string) do
    Logger.debug "Compiling t!(#{inspect lang}, #{inspect key}, string)"

    stripped = String.strip(string)
    args = Macro.var(:args, :polyglot)
    {:ok, parse_tree} = parse(stripped)
    ast = compile(parse_tree, %{lang: lang, args: args})

    {[lang, key, args], ast}
  end

  # Parse a string to an ast
  def parse(str) do
    {:ok, tokens} = tokenise(str, {"", [], 0})

    tokens
    |> Enum.filter(fn (t) -> t != "" end)
    |> parse_tree([])
  end

  # Tokenise a string
  defp tokenise("", {buffer, tokens, 0}) do
    {:ok, Enum.reverse [buffer|tokens]}
  end
  defp tokenise("", _) do
    {:error, "Unmatched opening bracket"}
  end
  defp tokenise(str, {buffer, tokens, b_depth}) do
    <<c::binary-size(1), rest::binary>> = str
    case {b_depth, c} do
      {_, "{"} ->
        tokenise(rest, {"", [:open, buffer | tokens], b_depth+1})
      {n, "}"} when n > 0 ->
        tokenise(rest, {"", [:close, buffer | tokens], b_depth-1})
      {_, "}"} -> {:error, "Unmatched closing bracket"}
      {n, ","} when n > 0 ->
        tokenise(rest, {"", [:comma, buffer | tokens], b_depth})
      {_, "#"} ->
        tokenise(rest, {"", [:hash, buffer | tokens], b_depth})
      {_, "\\"} ->
        <<c::binary-size(1), rest::binary>> = rest
        tokenise(rest, {buffer <> c, tokens, b_depth})
      {_, c} ->
        tokenise(rest, {buffer <> c, tokens, b_depth})
    end
  end

  # Parse tokens out into nested lists of list|tuple|string|atom
  defp parse_tree(tokens, output) do
    case tokens do
      [:open, arg, :close | rest] ->
        arg = arg |> String.strip |> String.downcase
        parse_tree(rest, [{:variable, arg}|output])
      [:open, arg, :comma, method, :comma | rest] ->
        {:partial, {body, rest}} = parse_body(rest, %{})

        method = case String.strip(method) do
          "select" -> :select
          "ordinal" -> :ordinal
          "plural" -> :plural
          "range" -> :range
        end

        arg = arg |> String.strip |> String.downcase

        parse_tree(rest, [{method, arg, body}|output])
      [:open | rest] ->
        {:partial, {clause, rest}} = parse_tree(rest, [])
        parse_tree(rest, [clause|output])
      [:close | rest] ->
        {:partial, {Enum.reverse(output), rest}}
      [x | rest] ->
        parse_tree(rest, [x|output])
      [] ->
        {:ok, Enum.reverse(output)}
    end
  end

  defp parse_body([value, :open | rest], output) do
    {:partial, {clause, rest}} = parse_tree(rest, [])
    parse_body(rest, Map.put(output, String.strip(value), clause))
  end
  defp parse_body([:close | rest], output) do
    {:partial, {output, rest}}
  end
  defp parse_body([other | rest], output) do
    case String.strip(other) do
      "" -> parse_body(rest, output)
      text -> {:unexpected, text}
    end
  end

  # Formatter compilers
  def compile({:select, arg, m}, env) do
    accessor = quote do
      unquote(env.args)[unquote(arg)]
    end

    clauses = Enum.map(m, fn({k, v}) ->
      {:->, [], [[k], compile(v, env)]}
    end)

    quote do
      case unquote(accessor) do
        unquote(clauses)
      end
    end
  end
  def compile({:ordinal, arg, m}, env) do
    accessor = quote do
      unquote(env.args)[unquote(arg)]
    end
    printer = quote do: to_string(unquote(accessor))

    clauses = Enum.map(m, fn({ k, v }) ->
      {:->, [], [[k], compile(v, Map.put(env, :printer, printer))]}
    end)

    quote do
      case plural(unquote(env.lang), :ordinal, unquote(accessor)) do
        unquote(clauses)
      end
    end
  end
  def compile({:plural, arg, m}, env) do
    accessor = quote do
      unquote(env.args)[unquote(arg)]
    end
    printer = quote do: to_string(unquote(accessor))

    clauses = Enum.map(m, fn({ k, v }) ->
      {:->, [], [[k], compile(v, Map.put(env, :printer, printer))]}
    end)

    quote do
      case plural(unquote(env.lang), :cardinal, unquote(accessor)) do
        unquote(clauses)
      end
    end
  end
  def compile({:range, arg, m}, env) do
    accessor = quote do
      unquote(env.args)[unquote(arg)]
    end
    printer = quote do: Polyglot.Compiler.format_range(unquote(accessor))

    clauses = Enum.map(m, fn({ k, v }) ->
      {:->, [], [[k], compile(v, Map.put(env, :printer, printer))]}
    end)

    quote do
      case plural(unquote(env.lang), :range, unquote(accessor)) do
        unquote(clauses)
      end
    end
  end

  # Generic recursive compile for lists and possibly stranded tokens
  def compile(tokens, env) when is_list(tokens) do
    for token <- tokens, do: compile(token, env)
  end
  def compile({:variable, var_name}, env) do
    quote do
      to_string unquote(env.args)[unquote(var_name)]
    end
  end
  def compile(:hash, env) do
    if Map.has_key?(env, :printer), do: env.printer, else: "#"
  end
  def compile(:comma, _env), do: ","
  def compile(s, _env) when is_bitstring(s), do: s

  # Output helpers
  def format_range({from, to}) do
    "#{to_string from}-#{to_string to}"
  end
end
