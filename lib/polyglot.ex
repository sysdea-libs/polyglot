defmodule Polyglot do
  require Polyglot.Plural

  defmacro __using__(_env) do
    quote do
      use Polyglot.Plural
      import Polyglot

      def t!(lang, key) do
        t!(lang, key, %{})
      end
    end
  end

  # defines a name(lang, key, options) function
  # eg compile_string(:t!, "en", "test", "my test string")
  defmacro locale_string(lang, key, string) do
    quote bind_quoted: binding do
      {args, body} = Polyglot.Compiler.compile_string!(lang, key, string)
      @plurals lang
      def t!(unquote_splicing(args)), do: to_string(unquote(body))
    end
  end

  defmacro locale(lang, path) do
    quote bind_quoted: binding do
      @external_resource path
      for {key, string} <- Polyglot.Compiler.load_file(path) do
        locale_string(lang, key, string)
      end
    end
  end
end
