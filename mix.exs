defmodule ReqAnthropic.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/mylanconnolly/req_anthropic"

  def project do
    [
      app: :req_anthropic,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ReqAnthropic.Application, []}
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5.6"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.15", only: [:dev, :test]}
    ]
  end

  defp description do
    "An Anthropic-focused API client built on Req."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
