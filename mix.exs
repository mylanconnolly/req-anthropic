defmodule ReqAnthropic.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/mylanconnolly/req_anthropic"
  @description "An Anthropic-focused API client for Elixir, built on Req."

  def project do
    [
      app: :req_anthropic,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: @description,
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url,
      name: "ReqAnthropic"
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
      {:plug, "~> 1.15", only: [:dev, :test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "req_anthropic",
      maintainers: ["Mylan Connolly"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => @source_url <> "/blob/main/CHANGELOG.md"
      },
      files: ~w(lib config/config.exs .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_modules: [
        "Core API": [
          ReqAnthropic,
          ReqAnthropic.Client,
          ReqAnthropic.Beta,
          ReqAnthropic.Error,
          ReqAnthropic.AuthError,
          ReqAnthropic.SSE
        ],
        Messages: [
          ReqAnthropic.Messages,
          ReqAnthropic.Conversation
        ],
        Models: [
          ReqAnthropic.Models,
          ReqAnthropic.Model,
          ReqAnthropic.Model.Capabilities
        ],
        "Files & Batches": [
          ReqAnthropic.Files,
          ReqAnthropic.Batches
        ],
        Tools: [
          ReqAnthropic.Tools
        ],
        "Managed Agents": [
          ReqAnthropic.Agents,
          ReqAnthropic.Environments,
          ReqAnthropic.Sessions,
          ReqAnthropic.Vaults,
          ReqAnthropic.Vaults.Credentials
        ]
      ]
    ]
  end
end
