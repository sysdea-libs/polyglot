defmodule Polyglot.Interpreter do
  alias Polyglot.Parser
  import Polyglot.Plural

  def interpret(lang, str, args \\ %{}) do
    {:ok, ast} = Parser.parse(str)
    interpret_ast(ast, %{lang: lang, printer: nil}, args)
  end

  def interpret_ast({:select, arg, m}, env, args) do
    v = Map.get(args, arg)
    case Map.get(m, v) do
      nil ->
        ["{Unknown SELECT option `", v, "`}"]
      node ->
        interpret_ast(node, %{env | printer: v}, args)
    end
  end

  def interpret_ast({:plural, arg, m}, env, args) do
    v = Map.get(args, arg)
    p = pluralise(env.lang, :cardinal, v)
    case Map.get(m, p) do
      nil ->
        ["{Uncovered PLURAL result `", p, "` from `", v, "`}"]
      node ->
        interpret_ast(node, %{env | printer: to_string(v)}, args)
    end
  end

  def interpret_ast({:ordinal, arg, m}, env, args) do
    v = Map.get(args, arg)
    p = pluralise(env.lang, :ordinal, v)
    case Map.get(m, p) do
      nil ->
        ["{Uncovered ORDINAL result `", p, "` from `", v, "`}"]
      node ->
        interpret_ast(node, %{env | printer: to_string(v)}, args)
    end
  end

  def interpret_ast({:range, arg, m}, env, args) do
    v = Map.get(args, arg)
    formatted_range = Polyglot.Compiler.format_range(v)
    p = pluralise(env.lang, :range, v)
    case Map.get(m, p) do
      nil ->
        ["{Uncovered RANGE result `", p, "` from `", formatted_range, "`}"]
      node ->
        interpret_ast(node, %{env | printer: formatted_range}, args)
    end
  end

  def interpret_ast(tokens, env, args) when is_list(tokens) do
    for token <- tokens, do: interpret_ast(token, env, args)
  end
  def interpret_ast({:variable, var_name}, _env, args) do
    to_string Map.get(args, var_name)
  end
  def interpret_ast(:hash, env, _args) do
    if Map.has_key?(env, :printer), do: env.printer, else: "#"
  end
  def interpret_ast(:comma, _env, _args), do: ","
  def interpret_ast(s, _env, _args) when is_bitstring(s) do
    s
  end
end
