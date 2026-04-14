defmodule ReqAnthropic.Conversation do
  @moduledoc """
  A small client-side helper for multi-turn Messages conversations.

  This is NOT a server resource — the Anthropic Messages API is stateless
  and each request carries the full history. `Conversation` just holds the
  accumulated messages plus optional system prompt and default request
  options so you don't have to rebuild the payload yourself.

  ## Example

      convo =
        ReqAnthropic.Conversation.new(
          model: "claude-haiku-4-5",
          max_tokens: 512,
          system: "You are a concise assistant."
        )
        |> ReqAnthropic.Conversation.user("Tell me about Elixir.")

      {:ok, convo} = ReqAnthropic.Conversation.send(convo)
      IO.puts(ReqAnthropic.Conversation.last_text(convo))

      convo =
        convo
        |> ReqAnthropic.Conversation.user("What about OTP?")

      {:ok, convo} = ReqAnthropic.Conversation.send(convo)
  """

  alias ReqAnthropic.Messages

  @enforce_keys [:model]
  defstruct model: nil,
            system: nil,
            messages: [],
            request_options: [],
            last_response: nil

  @type message :: %{required(:role) => String.t(), required(:content) => term()}
  @type t :: %__MODULE__{
          model: String.t(),
          system: String.t() | [map()] | nil,
          messages: [message()],
          request_options: keyword(),
          last_response: map() | nil
        }

  @doc """
  Build a new conversation. `:model` is required. Any other keyword is
  forwarded to `ReqAnthropic.Messages.create/1` on each `send/2` call,
  which includes `:api_key`, `:max_tokens`, `:temperature`, `:tools`,
  `:metadata`, `:system`, etc.
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    {model, opts} = Keyword.pop(opts, :model)
    {system, opts} = Keyword.pop(opts, :system)
    {initial, opts} = Keyword.pop(opts, :messages, [])

    unless is_binary(model), do: raise(ArgumentError, "model is required")

    %__MODULE__{
      model: model,
      system: system,
      messages: initial,
      request_options: opts
    }
  end

  @doc "Append a user message. `content` may be a string or a content-block list."
  @spec user(t(), String.t() | [map()]) :: t()
  def user(convo, content), do: append(convo, "user", content)

  @doc "Append an assistant message (e.g. from a prior response)."
  @spec assistant(t(), String.t() | [map()]) :: t()
  def assistant(convo, content), do: append(convo, "assistant", content)

  defp append(%__MODULE__{messages: msgs} = convo, role, content) do
    %{convo | messages: msgs ++ [%{role: role, content: content}]}
  end

  @doc """
  Send the conversation to the Messages API and return an updated
  `Conversation` with the assistant's reply appended.

  `extra_opts` are merged over the conversation's stored request options,
  so you can override `:max_tokens`, `:temperature`, etc. on a per-turn
  basis.
  """
  @spec send(t(), keyword()) :: {:ok, t()} | {:error, term()}
  def send(%__MODULE__{} = convo, extra_opts \\ []) do
    opts =
      convo.request_options
      |> Keyword.merge(extra_opts)
      |> Keyword.put(:model, convo.model)
      |> Keyword.put(:messages, convo.messages)
      |> maybe_put(:system, convo.system)

    case Messages.create(opts) do
      {:ok, message} ->
        content = Map.get(message, "content", [])
        updated = append(convo, "assistant", content)
        {:ok, %{updated | last_response: message}}

      {:error, _} = err ->
        err
    end
  end

  @doc "Return the plain text from the most recent assistant reply, if any."
  @spec last_text(t()) :: String.t()
  def last_text(%__MODULE__{last_response: nil}), do: ""

  def last_text(%__MODULE__{last_response: %{"content" => content}}) when is_list(content) do
    content
    |> Enum.filter(&match?(%{"type" => "text"}, &1))
    |> Enum.map(& &1["text"])
    |> Enum.join()
  end

  def last_text(%__MODULE__{}), do: ""

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
