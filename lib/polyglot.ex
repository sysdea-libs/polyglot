defmodule Polyglot do
  require Polyglot.Plural

  defmacro __using__(_env) do
    quote do
      import Polyglot

      def locale do
        if locale = Process.get(__MODULE__) do
          locale
        else
          locale = Application.get_env(:polyglot, :default_locale)
          Process.put(__MODULE__, locale)
          locale
        end
      end

      def locale(locale) do
        Process.put(__MODULE__, locale)
      end

      def t!(key) do
        ldt!(locale, "default", key, %{})
      end
      def t!(key, args) do
        ldt!(locale, "default", key, args)
      end

      def dt!(domain, key) do
        ldt!(locale, domain, key, %{})
      end
      def dt!(domain, key, args) do
        ldt!(locale, domain, key, args)
      end

      def lt!(lang, key) do
        ldt!(lang, "default", key, %{})
      end
      def lt!(lang, key, args) do
        ldt!(lang, "default", key, args)
      end

      def ldt!(lang, domain, key) do
        ldt!(lang, domain, key, %{})
      end
    end
  end

  defmacro load_directory(path) do
    quote do
      for lang <- File.ls!(unquote(path)) do
        messages_dir = Path.join([unquote(path), lang, "LC_MESSAGES"])
        for domain_file <- File.ls!(messages_dir) do
          [_, domain] = Regex.run(~r/(^.+)\.lang$/, domain_file)
          locale(lang, domain, Path.join([messages_dir, domain_file]))
        end
      end
    end
  end

  # defines a t!(lang, key, options) function
  # eg `locale_string "en", "test", "my test string"`
  defmacro locale_string(lang, domain, key, string) do
    quote bind_quoted: binding do
      {args, body} = Polyglot.Compiler.compile_string!(lang, domain, key, string)
      @plurals lang
      def ldt!(unquote_splicing(args)), do: unquote(body)
    end
  end

  # Loads locale_string definitions from a file
  # eg `locale "en", Path.join([__DIR__, "/locales/en.lang"])`
  defmacro locale(lang, domain, path) do
    quote bind_quoted: binding do
      @external_resource path
      for {key, string} <- Polyglot.Lang.load_file(path) do
        locale_string(lang, domain, key, string)
      end
    end
  end
end
