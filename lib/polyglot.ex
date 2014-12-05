defmodule Polyglot do
  require Polyglot.Plural
  require Logger

  defmacro __using__(_env) do
    quote do
      @before_compile Polyglot
      Module.register_attribute(__MODULE__, :translate_fns, accumulate: true)

      use Polyglot.Plural
      import Polyglot

      defp ensure_string(n) when is_bitstring(n), do: n
      defp ensure_string(n), do: inspect(n)
      defp format_range({from, to}) do
        "#{ensure_string from}-#{ensure_string to}"
      end
    end
  end

  # Shim in <name>/2 head function for each distinct function generated.
  defmacro __before_compile__(env) do
    fns = Module.get_attribute(env.module, :translate_fns)

    if is_atom(fns) do
      init_fn(fns)
    else
      fns
      |> Enum.into(HashSet.new)
      |> Enum.map(&init_fn(&1))
    end
  end

  defp init_fn(name) do
    quote do
      def unquote(name)(lang, key) do
        unquote(name)(lang, key, %{})
      end
    end
  end

  # defines a name(lang, key, options) function
  # eg compile_string(:t!, "en", "test", "my test string")
  defmacro function_from_string(name, lang, key, string) do
    quote bind_quoted: binding do
      {args, body} = compile_string!(lang, key, string)
      @plurals lang
      @translate_fns name
      def unquote(name)(unquote_splicing(args)), do: unquote(body)
    end
  end

  defmacro function_from_file(name, path) do
    quote bind_quoted: binding do
      for {lang, key, string} <- Polyglot.load_file(path) do
        function_from_string(name, lang, key, string)
      end
    end
  end

  def compile_string!(lang, key, string) do
    stripped = String.strip(string)
    args = Macro.var(:args, :polyglot)
    {:ok, parse_tree} = parse(stripped)
    ast = compile(parse_tree, %{lang: lang, args: args})

    Logger.debug fn ->
      """
      Compiled string:
      #{stripped}
        =>
      #{Macro.to_string(ast)}
      """
    end

    {[lang, key, args], ast}
  end

  # Load a file into [{lang, name, string}, ...]
  def load_file(path) do
    {lang, messages, name, buffer} = File.stream!(path)
                                     |> Enum.reduce({nil, [], nil, nil}, &parse_line(&1, &2))

    [{lang, name, String.strip(buffer)}|messages]
  end

  defp parse_line(line, state) do
    case {line, state} do
      {<<"LANG=", lang::binary>>, {_, [], nil, nil}} ->
        {String.strip(lang), [], nil, nil}
      {<<"LANG=", newlang::binary>>, {lang, messages, name, buffer}} ->
        {String.strip(newlang), [{lang, name, String.strip(buffer)}|messages], nil, nil}
      {<<"@", newname::binary>>, {lang, messages, nil, nil}} ->
        {lang, messages, String.strip(newname), ""}
      {<<"@", newname::binary>>, {lang, messages, name, buffer}} ->
        {lang, [{lang, name, String.strip(buffer)}|messages], String.strip(newname), ""}
      {<<"--", _::binary>>, state} ->
        state
      {_, {_, _, nil, nil}=state} ->
        state
      {line, {lang, messages, name, buffer}} ->
        {lang, messages, name, "#{buffer}\n#{line}"}
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

  defp parse_formatter([_arg, :comma, format | rest]=tokens) do
    check_arg(tokens, &formatter([&1, String.strip(format) | rest]))
  end
  defp parse_formatter(tokens), do: tokens

  defp parse_variable([_arg]=tokens) do
    check_arg(tokens, &({:variable, String.to_atom(&1)}))
  end
  defp parse_variable(tokens), do: tokens

  # include formatters
  use Polyglot.SelectFormat
  use Polyglot.OrdinalFormat
  use Polyglot.PluralFormat
  use Polyglot.RangeFormat

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

  # Generic recursive compile for lists and possibly stranded tokens
  def compile(tokens, env) when is_list(tokens) do
    tokens
    |> Enum.map(fn (t) -> compile(t, env) end)
    |> Enum.reduce(&quote do: unquote(&2) <> unquote(&1))
  end
  def compile({:variable, var_name}, env) do
    quote do
      ensure_string unquote(env.args)[unquote(var_name)]
    end
  end
  def compile(:hash, env) do
    if Map.has_key?(env, :printer), do: env.printer, else: "#"
  end
  def compile(:comma, _env), do: ","
  def compile(s, _env) when is_bitstring(s), do: s
end
