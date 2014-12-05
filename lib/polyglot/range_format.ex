defmodule Polyglot.RangeFormat do

  defmacro __using__(_env) do
    quote do

      defp formatter([arg, "range", :comma|body]) do
        {:range, arg, extract(body)}
      end

      def compile({:range, arg, m}, env) do
        arg = String.to_atom(arg)
        accessor = quote do
          unquote(env.args)[unquote(arg)]
        end
        printer = quote do: format_range(unquote(accessor))

        clauses = Enum.map(m, fn({ k, v }) ->
          {:->, [], [[k], compile(v, Map.put(env, :printer, printer))]}
        end)

        quote do
          case plural(unquote(env.lang), :range, unquote(accessor)) do
            unquote(clauses)
          end
        end
      end

    end
  end

end
