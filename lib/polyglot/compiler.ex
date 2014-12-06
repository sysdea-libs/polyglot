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

  # Load a file into [{lang, name, string}, ...]
  def load_file(path) do
    {messages, name, buffer} = File.stream!(path)
                               |> Enum.reduce({[], nil, nil}, &parse_line(&1, &2))

    [{name, String.strip(buffer)}|messages]
  end

  defp parse_line(line, state) do
    case {line, state} do
      {<<"@", newname::binary>>, {messages, nil, nil}} ->
        {messages, String.strip(newname), ""}
      {<<"@", newname::binary>>, {messages, name, buffer}} ->
        {[{name, String.strip(buffer)}|messages], String.strip(newname), ""}
      {<<"--", _::binary>>, state} ->
        state
      {_, {_, nil, nil}=state} ->
        state
      {line, {messages, name, buffer}} ->
        {messages, name, "#{buffer}\n#{line}"}
    end
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
      [:hash, :open | rest] ->
        {:partial, {clause, rest}} = parse_tree(rest, [])
        parse_tree(rest, [parse_variable(clause)|output])
      [:open | rest] ->
        {:partial, {clause, rest}} = parse_tree(rest, [])
        parse_tree(rest, [parse_formatter(clause)|output])
      [:close | rest] ->
        {:partial, {Enum.reverse(output), rest}}
      [x | rest] ->
        parse_tree(rest, [x|output])
      [] ->
        {:ok, Enum.reverse(output)}
    end
  end

  # Checks head of list to be a valid variable identifier, and if so
  # calls the passed fn with it, otherwise returning the full token list.
  # Doesn't atomise the var name yet, due to possible false positives.
  defp check_arg([arg|_rest]=tokens, f) do
    var_name = arg |> String.strip |> String.downcase
    if Regex.match?(~r/^[a-z][a-z0-9_-]*$/, var_name) do
      f.(var_name)
    else
      tokens
    end
  end

  defp parse_variable([_arg]=tokens) do
    check_arg(tokens, &({:variable, String.to_atom(&1)}))
  end
  defp parse_variable(tokens), do: tokens

  defp parse_formatter([_arg, :comma, format | rest]=tokens) do
    check_arg(tokens, &formatter([&1, String.strip(format) | rest]))
  end
  defp parse_formatter(tokens), do: tokens

  # Match formatters
  defp formatter([arg, "select", :comma|body]) do
    {:select, arg, extract(body)}
  end
  defp formatter([arg, "ordinal", :comma|body]) do
    {:ordinal, arg, extract(body)}
  end
  defp formatter([arg, "plural", :comma|body]) do
    {:plural, arg, extract(body)}
  end
  defp formatter([arg, "range", :comma|body]) do
    {:range, arg, extract(body)}
  end
  defp formatter(tokens), do: tokens

  # Transform a list of tokens into a map
  # Helper function used by the Formatters
  # [" a ", :hash, "c  ", ["my data"]] -> %{"a"=>:hash, "c"=>["my data"]}
  defp extract(tokens) do
    for [k,v] <- tokens
                 |> Enum.map(fn s when is_bitstring(s) -> String.strip(s)
                                t -> t end)
                 |> Enum.filter(&(&1 != ""))
                 |> Enum.chunk(2), do: {k, v}, into: %{}
  end

  # Formatter compilers
  def compile({:select, arg, m}, env) do
    arg = String.to_atom(arg)
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
    arg = String.to_atom(arg)
    accessor = quote do
      unquote(env.args)[unquote(arg)]
    end
    printer = quote do: Polyglot.Compiler.ensure_string(unquote(accessor))

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
    arg = String.to_atom(arg)
    accessor = quote do
      unquote(env.args)[unquote(arg)]
    end
    printer = quote do: Polyglot.Compiler.ensure_string(unquote(accessor))

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
    arg = String.to_atom(arg)
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
    tokens
    |> Enum.map(fn (t) -> compile(t, env) end)
    |> Enum.reduce(&quote do: unquote(&2) <> unquote(&1))
  end
  def compile({:variable, var_name}, env) do
    quote do
      Polyglot.Compiler.ensure_string unquote(env.args)[unquote(var_name)]
    end
  end
  def compile(:hash, env) do
    if Map.has_key?(env, :printer), do: env.printer, else: "#"
  end
  def compile(:comma, _env), do: ","
  def compile(s, _env) when is_bitstring(s), do: s

  # Output helpers
  def ensure_string(n) when is_bitstring(n), do: n
  def ensure_string(n), do: inspect(n)
  def format_range({from, to}) do
    "#{ensure_string from}-#{ensure_string to}"
  end
end
