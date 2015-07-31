defmodule Polyglot do
  require Polyglot.Plural

  defmacro __using__(_env) do
    quote do
      import Polyglot

      def t!(lang, key) do
        t!(lang, key, %{})
      end
    end
  end

  # defines a t!(lang, key, options) function
  # eg `locale_string "en", "test", "my test string"`
  defmacro locale_string(lang, key, string) do
    quote bind_quoted: binding do
      {args, body} = Polyglot.Compiler.compile_string!(lang, key, string)
      @plurals lang
      def t!(unquote_splicing(args)), do: unquote(body)
    end
  end

  # Loads locale_string definitions from a file
  # eg `locale "en", Path.join([__DIR__, "/locales/en.lang"])`
  defmacro locale(lang, path) do
    quote bind_quoted: binding do
      @external_resource path
      for {key, string} <- Polyglot.Lang.load_file(path) do
        locale_string(lang, key, string)
      end
    end
  end
end
