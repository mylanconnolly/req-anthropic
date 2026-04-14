defmodule ReqAnthropic.Beta do
  @moduledoc """
  Helpers for managing the `anthropic-beta` request header.

  Anthropic accepts one or more beta opt-ins as a comma-separated list. This
  module normalizes the various shapes (string, list, nil) into a deduped
  list and into the comma-joined header value.
  """

  @type t :: String.t() | [String.t()] | nil

  @doc """
  Merge any number of beta values into a single deduped list, preserving
  the order of first appearance.
  """
  @spec merge([t()]) :: [String.t()]
  def merge(values) do
    values
    |> Enum.flat_map(&normalize/1)
    |> Enum.uniq()
  end

  @doc "Normalize a single value into a list of beta strings."
  @spec normalize(t()) :: [String.t()]
  def normalize(nil), do: []
  def normalize(""), do: []
  def normalize(value) when is_binary(value), do: [value]
  def normalize(values) when is_list(values), do: Enum.flat_map(values, &normalize/1)

  @doc "Render a list of beta values as the comma-joined header value, or nil if empty."
  @spec header_value([String.t()]) :: String.t() | nil
  def header_value([]), do: nil
  def header_value(values), do: Enum.join(values, ",")

  @doc """
  Ensure one or more beta values are present on a keyword list of client
  options, merging with anything already there. Used by resource modules
  that gate on a specific beta header (files, managed agents, advisor).
  """
  @spec ensure(keyword(), String.t() | [String.t()]) :: keyword()
  def ensure(opts, required) do
    Keyword.update(opts, :beta, List.wrap(required), fn existing ->
      merge([existing, required])
    end)
  end
end
