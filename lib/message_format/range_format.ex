defmodule MessageFormat.RangeFormat do

  defmacro __using__(_env) do
    quote do

      defp formatter([arg, "range", :comma|body]) do
        {:range, arg, extract(body)}
      end

      def compile({:range, arg, m}, env) do
        arg = arg |> String.downcase |> String.to_atom
        accessor = quote do
          unquote(var(:args))[unquote(arg)]
        end
        printer = quote do
          ensure_string(elem(unquote(accessor), 0))
          <> "-" <>
          ensure_string(elem(unquote(accessor), 1))
        end

        clauses = Enum.map(m, fn({ k, v }) ->
          {:->, [], [[k], compile(v, Map.put(env, :printer, printer))]}
        end)

        quote do
          case plural(unquote(env.lang), unquote(accessor), :range) do
            unquote(clauses)
          end
        end
      end

    end
  end

end
