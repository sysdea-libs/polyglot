defmodule Polyglot.PluralFormat do

  defmacro __using__(_env) do
    quote do

      defp formatter([arg, "plural", :comma|body]) do
        {:plural, arg, extract(body)}
      end

      def compile({:plural, arg, m}, env) do
        arg = String.to_atom(arg)
        accessor = quote do
          unquote(env.args)[unquote(arg)]
        end
        printer = quote do: ensure_string(unquote(accessor))

        clauses = Enum.map(m, fn({ k, v }) ->
          {:->, [], [[k], compile(v, Map.put(env, :printer, printer))]}
        end)

        quote do
          case plural(unquote(env.lang), :cardinal, unquote(accessor)) do
            unquote(clauses)
          end
        end
      end

    end
  end

end
