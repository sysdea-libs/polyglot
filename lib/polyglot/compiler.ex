defmodule Polyglot.Compiler do
  alias Polyglot.Parser
  require Logger

  def compile_string!(lang, key, string) do
    Logger.debug "Compiling t!(#{inspect lang}, #{inspect key}, string)"

    stripped = String.strip(string)
    args = Macro.var(:args, :polyglot)
    {:ok, parse_tree} = Parser.parse(stripped)
    ast = compile(parse_tree, %{lang: lang, args: args})

    {[lang, key, args], ast}
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
      case Polyglot.Plural.pluralise(unquote(env.lang), :ordinal, unquote(accessor)) do
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
      case Polyglot.Plural.pluralise(unquote(env.lang), :cardinal, unquote(accessor)) do
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
      case Polyglot.Plural.pluralise(unquote(env.lang), :range, unquote(accessor)) do
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
