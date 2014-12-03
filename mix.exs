defmodule Polyglot.Mixfile do
  use Mix.Project

  def project do
    [app: :polyglot,
     version: "0.0.1",
     elixir: "~> 1.0",
     deps: deps,
     package: [
      contributors: ["Chris Spencer"],
      licenses: ["MIT"],
      links: %{github: "https://github.com/strategydynamics/polyglot"}
     ],
     description: "MessageFormat-like implementation (Select/Plural/Range/Ordinal) for i18n."]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: [:logger]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    []
  end
end
