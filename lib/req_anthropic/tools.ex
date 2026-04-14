defmodule ReqAnthropic.Tools do
  @moduledoc """
  Builders for Anthropic tool definitions, so callers don't need to
  memorize tool type strings or beta header names.

  Each builder returns a plain map suitable for passing in `tools: [...]`
  on a Messages request. Tools that depend on a beta header expose the
  beta string via `beta_header/1` and via the `:beta` key on the map, so
  the calling resource module can wire it up automatically.

      tools = [
        ReqAnthropic.Tools.web_search(),
        ReqAnthropic.Tools.bash(),
        ReqAnthropic.Tools.custom(name: "get_weather", description: "...", input_schema: %{...})
      ]

      ReqAnthropic.Messages.create(model: "...", max_tokens: 1024, tools: tools, messages: [...])
  """

  @web_search_type "web_search_20250305"
  @web_fetch_type "web_fetch_20250910"
  @bash_type "bash_20250124"
  @text_editor_type "text_editor_20250728"
  @computer_type "computer_20250124"
  @memory_type "memory_20250818"
  @advisor_type "advisor_20260301"

  @advisor_beta "advisor-tool-2026-03-01"
  @computer_beta "computer-use-2025-01-24"

  @doc "Web search tool. Pass `:max_uses` to cap searches per request."
  @spec web_search(keyword()) :: map()
  def web_search(opts \\ []) do
    base = %{type: @web_search_type, name: "web_search"}

    opts
    |> Keyword.take([:max_uses, :allowed_domains, :blocked_domains, :user_location])
    |> Enum.into(base)
  end

  @doc "Web fetch tool."
  @spec web_fetch(keyword()) :: map()
  def web_fetch(opts \\ []) do
    base = %{type: @web_fetch_type, name: "web_fetch"}

    opts
    |> Keyword.take([:max_uses, :allowed_domains, :blocked_domains, :max_content_tokens])
    |> Enum.into(base)
  end

  @doc "Built-in bash tool."
  @spec bash(keyword()) :: map()
  def bash(_opts \\ []) do
    %{type: @bash_type, name: "bash"}
  end

  @doc """
  Built-in text editor tool. The default name `str_replace_based_edit_tool`
  is what the Claude 4 family expects; override with `:name` if you need
  a different binding.
  """
  @spec text_editor(keyword()) :: map()
  def text_editor(opts \\ []) do
    %{type: @text_editor_type, name: Keyword.get(opts, :name, "str_replace_based_edit_tool")}
  end

  @doc """
  Computer use tool. Required: `:display_width_px`, `:display_height_px`.
  Optional: `:display_number`. Adds the `computer-use-2025-01-24` beta.
  """
  @spec computer(keyword()) :: map()
  def computer(opts) do
    base = %{
      type: @computer_type,
      name: "computer",
      display_width_px: Keyword.fetch!(opts, :display_width_px),
      display_height_px: Keyword.fetch!(opts, :display_height_px),
      __beta__: @computer_beta
    }

    case Keyword.get(opts, :display_number) do
      nil -> base
      n -> Map.put(base, :display_number, n)
    end
  end

  @doc "Memory tool."
  @spec memory(keyword()) :: map()
  def memory(_opts \\ []) do
    %{type: @memory_type, name: "memory"}
  end

  @doc "Advisor tool. Adds the `advisor-tool-2026-03-01` beta header."
  @spec advisor(keyword()) :: map()
  def advisor(_opts \\ []) do
    %{type: @advisor_type, name: "advisor", __beta__: @advisor_beta}
  end

  @doc "Define a custom tool with a JSON Schema input."
  @spec custom(keyword()) :: map()
  def custom(opts) do
    %{
      name: Keyword.fetch!(opts, :name),
      description: Keyword.fetch!(opts, :description),
      input_schema: Keyword.fetch!(opts, :input_schema)
    }
  end

  @doc """
  Collect any beta header strings required by a list of tool maps. The
  resource modules use this to merge required betas into the request
  before sending.
  """
  @spec required_betas([map()]) :: [String.t()]
  def required_betas(tools) when is_list(tools) do
    Enum.flat_map(tools, fn
      %{__beta__: beta} -> [beta]
      _ -> []
    end)
  end

  @doc """
  Strip internal `__beta__` markers from a list of tool maps so they can
  be safely sent over the wire.
  """
  @spec strip([map()]) :: [map()]
  def strip(tools) when is_list(tools) do
    Enum.map(tools, &Map.delete(&1, :__beta__))
  end
end
