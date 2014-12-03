defmodule MessageFormat do
  require MessageFormat.Plural

  defmacro __using__(_env) do
    quote do
      @before_compile MessageFormat
      Module.register_attribute(__MODULE__, :translate_fns, accumulate: true)

      use MessageFormat.Plural
      import MessageFormat

      defp ensure_string(n) when is_bitstring(n), do: n
      defp ensure_string(n), do: inspect(n)
    end
  end

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

  # Helper function to generate var references
  defp var(name), do: {name, [], :plural}

  # defines a name(lang, key, options) function
  # eg compile_string(:t!, "en", "test", "my test string")
  defmacro compile_string(name, lang, key, string) do
    compiled = MessageFormat.compile(MessageFormat.parse(string), %{lang: lang})

    quote do
      @plurals unquote(lang)
      @translate_fns unquote(name)
      def unquote(name)(unquote(lang), unquote(key), unquote(var(:args))) do
        String.strip(unquote(compiled))
      end
    end
  end

  # Parse a string to an ast
  def parse(str) do
    {:ok, tokens} = tokenise(str, { "", [], 0 })

    tokens
    |> Enum.filter(fn (t) -> t != "" end)
    |> parse_tree([])
  end

  # Tokenise a string
  defp tokenise("", { buffer, tokens, 0 }) do
    {:ok, Enum.reverse [buffer|tokens]}
  end
  defp tokenise("", { _buffer, _tokens, _ }) do
    {:error, "Unmatched opening bracket"}
  end
  defp tokenise(str, { buffer, tokens, b_depth }) do
    <<c::binary-size(1), rest::binary>> = str
    case { b_depth, c } do
      {_, "{"} ->
        tokenise(rest, { "", [:open, buffer | tokens], b_depth+1})
      {n, "}"} when n > 0 ->
        tokenise(rest, { "", [:close, buffer | tokens], b_depth-1})
      {_, "}"} -> {:error, "Unmatched closing bracket"}
      {n, ","} when n > 0 ->
        tokenise(rest, { "", [:comma, buffer | tokens], b_depth })
      {n, "#"} when n > 0 ->
        tokenise(rest, { "", [:hash, buffer | tokens], b_depth })
      {_, "\\"} ->
        <<c::binary-size(1), rest::binary>> = rest
        tokenise(rest, { buffer <> c, tokens, b_depth })
      {_, c} ->
        tokenise(rest, { buffer <> c, tokens, b_depth })
    end
  end

  # Parse tokens out into an ast
  defp parse_tree(tokens, olist) do
    case tokens do
      [:open | rest] ->
        { clause, rest } = parse_tree(rest, [])
        clause = parse_clause(clause)
        parse_tree(rest, [clause|olist])
      [:close | rest] ->
        { Enum.reverse(olist), rest }
      [x | rest] ->
        parse_tree(rest, [x|olist])
      [] ->
        Enum.reverse(olist)
    end
  end

  # takes a bracketed clause and returns either a string or a
  # tuple describing the operation
  defp parse_clause([op1, :comma, op2 | rest]) do
    command = String.strip(op2)
    formatter([op1, command | rest])
  end
  defp parse_clause(tokens), do: tokens

  # include formatters
  use MessageFormat.SelectFormat
  use MessageFormat.OrdinalFormat
  use MessageFormat.PluralFormat
  use MessageFormat.RangeFormat

  # recognise select/plural formatters

  defp formatter(tokens), do: tokens

  # Transform a list of tokens into a map
  # [a b c d] -> %{"a"=>"b", "c"=>"d"}
  defp extract(tokens) do
    tokens
    |> clean_tokens
    |> extract_map(%{})
  end

  defp extract_map([key, value|rest], m) do
    extract_map(rest, Map.put(m, String.strip(key), value))
  end
  defp extract_map([], m), do: m

  defp clean_tokens(tokens) do
    Enum.reduce(tokens, [], fn (r, acc) ->
      if is_bitstring(r) do
        case String.strip(r) do
          "" -> acc
          str -> [str|acc]
        end
      else
        [r|acc]
      end
    end)
    |> Enum.reverse
  end

  # Recursively compile lists
  def compile(tokens, env) when is_list(tokens) do
    tokens
    |> Enum.map(fn (t) -> compile(t, env) end)
    |> Enum.reduce(&quote do: unquote(&2) <> unquote(&1))
  end

  def compile(:hash, env) do
    if Map.has_key?(env, :printer) do
      env.printer
    else
      "#"
    end
  end

  def compile(:comma, _env), do: ","
  def compile(s, _env) when is_bitstring(s), do: s
end
