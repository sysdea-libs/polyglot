defmodule Polyglot.Lang do

  # Load a file into [{name, string}, ...]
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
      {<<";", _::binary>>, state} ->
        state
      {_, {_, nil, nil}=state} ->
        state
      {line, {messages, name, buffer}} ->
        {messages, name, "#{buffer}\n#{line}"}
    end
  end
end
