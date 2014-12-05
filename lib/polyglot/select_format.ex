defmodule Polyglot.SelectFormat do

  defmacro __using__(_env) do
    quote do

      defp formatter([arg, "select", :comma|body]) do
        {:select, arg, extract(body)}
      end

      def compile({:select, arg, m}, env) do
        arg = String.to_atom(arg)
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

    end
  end

end
