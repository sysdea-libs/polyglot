defmodule Polyglot do
  require Polyglot.Plural

  defmacro __using__(_env) do
    quote do
      @before_compile Polyglot
      Module.register_attribute(__MODULE__, :translate_fns, accumulate: true)

      use Polyglot.Plural
      import Polyglot

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
  defmacro function_from_string(name, lang, key, string) do
    quote bind_quoted: binding do
      {args, body} = compile_string(lang, key, string)
      @plurals lang
      @translate_fns name
      def unquote(name)(unquote_splicing(args)), do: unquote(body)
    end
  end

  defmacro function_from_file(name, path) do
    quote bind_quoted: binding do
      for {lang, key, string} <- Polyglot.load_file(path) do
        { args, body } = compile_string(lang, key, string)
        @plurals lang
        @translate_fns name
        def unquote(name)(unquote_splicing(args)), do: unquote(body)
      end
    end
  end

  def compile_string(lang, key, string) do
    compiled = Polyglot.compile(Polyglot.parse(string), %{lang: lang})

    { [lang, key, var(:args)], quote(do: String.strip(unquote(compiled))) }
  end

  # Load a file into [{ lang, name, string }, ...]
  def load_file(path) do
    {:ok, file_contents} = :file.read_file(path)
    lines = String.split(file_contents, ~r/\r?\n/)

    { lang, messages, name, buffer } =
      Enum.reduce(lines, { nil, [], nil, nil }, &parse_line(&1, &2))

    [{ lang, name, String.strip(buffer) }|messages]
  end

  defp parse_line(<<"LANG=", lang::binary>>, { _lang, [], nil, nil }) do
    { String.strip(lang), [], nil, nil }
  end
  defp parse_line(<<"LANG=", newlang::binary>>, { lang, messages, name, buffer }) do
    { String.strip(newlang), [{ lang, name, String.strip(buffer) }|messages], nil, nil }
  end
  defp parse_line(<<"@", newname::binary>>, { lang, messages, nil, nil }) do
    { lang, messages, String.strip(newname), "" }
  end
  defp parse_line(<<"@", newname::binary>>, { lang, messages, name, buffer }) do
    { lang, [{ lang, name, String.strip(buffer) }|messages], String.strip(newname), "" }
  end
  defp parse_line(<<"--", _commented::binary>>, state) do
    state
  end
  defp parse_line(_line, { lang, messages, nil, nil }) do
    { lang, messages, nil, nil }
  end
  defp parse_line(line, { lang, messages, name, buffer }) do
    { lang, messages, name, buffer <> "\n" <> line }
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

  # Parse tokens out into nested lists of list|tuple|string|atom
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

  # takes a bracketed clause and returns either the list of tokens back or a
  # tuple describing a formatting node
  defp parse_clause([op1, :comma, op2 | rest]) do
    command = String.strip(op2)
    formatter([op1, command | rest])
  end
  defp parse_clause(tokens), do: tokens

  # include formatters
  use Polyglot.SelectFormat
  use Polyglot.OrdinalFormat
  use Polyglot.PluralFormat
  use Polyglot.RangeFormat

  defp formatter(tokens), do: tokens

  # Transform a list of tokens into a map
  # Helper function used by the Formatters
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

  # Generic recursive compile for lists and possibly stranded tokens
  def compile(tokens, env) when is_list(tokens) do
    tokens
    |> Enum.map(fn (t) -> compile(t, env) end)
    |> Enum.reduce(&quote do: unquote(&2) <> unquote(&1))
  end
  def compile(:hash, env) do
    if Map.has_key?(env, :printer), do: env.printer, else: "#"
  end
  def compile(:comma, _env), do: ","
  def compile(s, _env) when is_bitstring(s), do: s
end
