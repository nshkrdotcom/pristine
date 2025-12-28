defmodule Pristine.MixProject do
  use Mix.Project

  def project do
    [
      app: :pristine,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Manifest-driven hexagonal core for generating Elixir SDKs and services.",
      package: package(),
      dialyzer: dialyzer()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :telemetry],
      mod: {Pristine.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      {:finch, "~> 0.18"},
      {:sinter, path: "../sinter"},
      {:foundation, path: "../foundation"},
      {:multipart_ex, path: "../multipart_ex"},
      {:telemetry_reporter, path: "../telemetry_reporter"},
      {:tiktoken_ex, path: "../../North-Shore-AI/tiktoken_ex"},
      {:uuid, "~> 1.1"},
      {:mox, "~> 1.1", only: :test},
      {:plug, "~> 1.15", only: :dev},
      {:plug_cowboy, "~> 2.7", only: :dev},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/nshkrdotcom/pristine"
      }
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end
end
