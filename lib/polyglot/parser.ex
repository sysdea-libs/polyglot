defmodule Polyglot.Parser do

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
end
