defmodule Polyglot.Compiler do
  alias Polyglot.Parser
  require Logger

  def compile_string!(lang, domain, key, string) do
    Logger.debug "Compiling t!(#{inspect lang}, #{inspect key}, string)"

    stripped = String.strip(string)
    args = Macro.var(:args, :polyglot)
    {:ok, parse_tree} = Parser.parse(stripped)
    ast = compile(parse_tree, %{lang: lang, args: args})

    {[lang, domain, key, args], ast}
  end

  defp clause(k, v) do
    {:->, [], [[k], v]}
  end

  # General cardinal/ordinal generator
  defp compile_plural(kind, arg, m, env) do
    accessor = quote do
      unquote(env.args)[unquote(arg)]
    end
    printer = quote do: to_string(unquote(accessor))
    env = Map.put(env, :printer, printer)

    # Extract the specific clauses like =0 from the categories
    {specific, general} = Enum.partition(m, fn
                                            {<<"=", _>>, _} -> true
                                            _ -> false
                                          end)

    # Compile the general case
    general_clauses = for {k, v} <- general, do: clause(k, compile(v, env))

    general_case = quote do
      case Polyglot.Plural.pluralise(unquote(env.lang), unquote(kind), unquote(accessor)) do
        unquote(general_clauses)
      end
    end

    # Compile the specific case, skipping it if there are no specific clauses
    case Enum.count(specific) do
      0 ->
        general_case
      _ ->
        clauses = for {<<"=", k::binary>>, v} <- specific do
          clause(k, compile(v, env))
        end
        clauses = clauses ++ [clause(Macro.var(:_, :polyglot), general_case)]

        quote do
          case to_string(unquote(accessor)) do
            unquote(clauses)
          end
        end
    end
  end

  # Formatter compilers
  def compile({:select, arg, m}, env) do
    accessor = quote do
      unquote(env.args)[unquote(arg)]
    end
    printer = quote do: to_string(unquote(accessor))

    env = Map.put(env, :printer, printer)
    clauses = for {k, v} <- m, do: clause(k, compile(v, env))

    fallthrough = case m["other"] do
      nil ->
        quote do
          ["{Unknown SELECT option `", unquote(printer), "` with arg `", unquote(arg), "`}"]
        end
      v ->
        compile(v, env)
    end

    clauses = clauses ++ [clause(Macro.var(:_, :polyglot), fallthrough)]

    quote do
      case unquote(accessor) do
        unquote(clauses)
      end
    end
  end
  def compile({:ordinal, arg, m}, env) do
    compile_plural(:ordinal, arg, m, env)
  end
  def compile({:plural, arg, m}, env) do
    compile_plural(:cardinal, arg, m, env)
  end
  def compile({:range, arg, m}, env) do
    accessor = quote do
      unquote(env.args)[unquote(arg)]
    end
    printer = quote do: Polyglot.Compiler.format_range(unquote(accessor))

    env = Map.put(env, :printer, printer)
    clauses = for {k, v} <- m, do: clause(k, compile(v, env))

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
