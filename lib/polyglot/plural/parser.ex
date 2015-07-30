defmodule Polyglot.Plural.Parser do
  # Parse a string into {tree, deps}
  def parse("") do
    {true, HashSet.new}
  end
  def parse(str) do
    {tokens, deps} = tokenise(str, [], HashSet.new)
    {parse_tree(tokens, [], []), deps}
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
        v = Macro.var(String.to_atom(c), :plural)
        if c == "n" do
          tokenise(str, [{:var,v}|tokens], deps)
        else
          tokenise(str, [{:var,v}|tokens], Set.put(deps, v))
        end

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
  @precedences %{or: 1,
                 and: 2,
                 neq: 3, eq: 3,
                 mod: 4,
                 comma: 5,
                 range: 6}

  defp parse_tree(tokens, opstack, output) do
    case {tokens, opstack, output} do
      {[], [], [result]} ->
        result
      {[], [op|opstack], output} ->
        push_op(op, [], opstack, output)
      {[{:op, o1}|rest], [], output} ->
        parse_tree(rest, [o1], output)
      {[{:op, o1}|rest]=tokens, [o2|opstack], output} ->
        if @precedences[o1] <= @precedences[o2] do
          push_op(o2, tokens, opstack, output)
        else
          parse_tree(rest, [o1,o2|opstack], output)
        end
      {[node|rest], opstack, output} ->
        parse_tree(rest, opstack, [node|output])
    end
  end

  defp push_op(op, tokens, opstack, [r,l|output]) do
    case {op, l} do
      {:comma, {:list, vs}} ->
        parse_tree(tokens, opstack, [{:list, [r|vs]}|output])
      {:comma, _} ->
        parse_tree(tokens, opstack, [{:list, [r,l]}|output])
      _ ->
        parse_tree(tokens, opstack, [{:binary, op, l, r}|output])
    end
  end
end
