defmodule ReqAnthropic.Model do
  @moduledoc """
  Struct representation of an Anthropic model and its capabilities.
  """

  defstruct [:id, :display_name, :type, :created_at, :raw]

  @type t :: %__MODULE__{
          id: String.t(),
          display_name: String.t() | nil,
          type: String.t() | nil,
          created_at: String.t() | nil,
          raw: map() | nil
        }

  @doc "Build a Model struct from an Anthropic API response map."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: Map.get(map, "id"),
      display_name: Map.get(map, "display_name"),
      type: Map.get(map, "type"),
      created_at: Map.get(map, "created_at"),
      raw: map
    }
  end

  defmodule Capabilities do
    @moduledoc """
    Per-model capability flags. Anthropic doesn't currently expose these on
    `GET /v1/models`, so the table is hard-coded here. Update this module
    when models change.
    """

    defstruct [
      :id,
      :supports_vision,
      :supports_extended_thinking,
      :supports_computer_use,
      :supports_pdf,
      :supports_prompt_caching,
      :max_input_tokens,
      :max_output_tokens
    ]

    @type t :: %__MODULE__{
            id: String.t(),
            supports_vision: boolean(),
            supports_extended_thinking: boolean(),
            supports_computer_use: boolean(),
            supports_pdf: boolean(),
            supports_prompt_caching: boolean(),
            max_input_tokens: pos_integer() | nil,
            max_output_tokens: pos_integer() | nil
          }

    @table %{
      "claude-opus-4-6" => %{
        supports_vision: true,
        supports_extended_thinking: true,
        supports_computer_use: true,
        supports_pdf: true,
        supports_prompt_caching: true,
        max_input_tokens: 200_000,
        max_output_tokens: 32_000
      },
      "claude-sonnet-4-6" => %{
        supports_vision: true,
        supports_extended_thinking: true,
        supports_computer_use: true,
        supports_pdf: true,
        supports_prompt_caching: true,
        max_input_tokens: 200_000,
        max_output_tokens: 64_000
      },
      "claude-haiku-4-5" => %{
        supports_vision: true,
        supports_extended_thinking: true,
        supports_computer_use: false,
        supports_pdf: true,
        supports_prompt_caching: true,
        max_input_tokens: 200_000,
        max_output_tokens: 32_000
      },
      "claude-opus-4-5" => %{
        supports_vision: true,
        supports_extended_thinking: true,
        supports_computer_use: true,
        supports_pdf: true,
        supports_prompt_caching: true,
        max_input_tokens: 200_000,
        max_output_tokens: 32_000
      },
      "claude-sonnet-4-5" => %{
        supports_vision: true,
        supports_extended_thinking: true,
        supports_computer_use: true,
        supports_pdf: true,
        supports_prompt_caching: true,
        max_input_tokens: 200_000,
        max_output_tokens: 64_000
      }
    }

    @doc "Look up capabilities for a model id, falling back to a conservative default."
    @spec for_id(String.t()) :: t()
    def for_id(id) when is_binary(id) do
      base = canonicalize(id)

      data =
        Map.get(@table, base, %{
          supports_vision: false,
          supports_extended_thinking: false,
          supports_computer_use: false,
          supports_pdf: false,
          supports_prompt_caching: true,
          max_input_tokens: nil,
          max_output_tokens: nil
        })

      struct(__MODULE__, Map.put(data, :id, id))
    end

    defp canonicalize(id) do
      Enum.find(Map.keys(@table), id, fn key -> String.starts_with?(id, key) end)
    end
  end
end
