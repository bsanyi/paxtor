defmodule Paxtor.MixProject do
  use Mix.Project

  def project do
    [
      app: :paxtor,
      package: package(),
      version: "0.3.0",
      elixir: "~> 1.17 or ~> 1.18 or ~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  defp package() do
    [
      description: "App for building CP (Consistent and Partition-tolerant) distributed systems.",
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/bsanyi/paxtor"}
    ]
  end

  def application do
    [
      extra_applications: extra_apps(Mix.env()),
      mod: {Paxtor.Application, []}
    ]
  end

  defp extra_apps(:dev), do: [:logger, :wx, :observer]
  defp extra_apps(_), do: [:logger]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:paxos_kv, "~> 0.6.0"}
    ]
  end
end
