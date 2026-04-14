defmodule ReqAnthropic.Client do
  @moduledoc """
  Internal builder used by every resource module. It guarantees that all
  resource calls share the same option-resolution and step-attachment
  pipeline, so cross-cutting concerns (auth, error decoding, test stubs)
  live in exactly one place.
  """

  @default_receive_timeout 120_000

  @doc """
  Build a `%Req.Request{}` with ReqAnthropic attached.

  Recognized keys:

    * Any ReqAnthropic option (see `ReqAnthropic.attach/2`)
    * `:req_options` - keyword forwarded directly to `Req.merge/2` after
      attach, so callers can set `:retry`, `:finch`, `:receive_timeout`, etc.

  The default `receive_timeout` is #{@default_receive_timeout}ms (2 minutes),
  since LLM API calls regularly exceed Finch's 15-second default.
  """
  @spec build(keyword()) :: Req.Request.t()
  def build(opts \\ []) do
    {req_options, anthropic_opts} = Keyword.pop(opts, :req_options, [])
    req_options = Keyword.put_new(req_options, :receive_timeout, @default_receive_timeout)

    Req.new()
    |> ReqAnthropic.attach(anthropic_opts)
    |> Req.merge(req_options)
    |> maybe_attach_test_plug()
  end

  defp maybe_attach_test_plug(req) do
    case Application.get_env(:req_anthropic, :plug) do
      nil -> req
      plug -> Req.merge(req, plug: plug)
    end
  end
end
