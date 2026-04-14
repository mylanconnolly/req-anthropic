defmodule ReqAnthropic.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :ets.new(ReqAnthropic.Models.Cache, [
      :named_table,
      :public,
      :set,
      read_concurrency: true
    ])

    Supervisor.start_link([], strategy: :one_for_one, name: ReqAnthropic.Supervisor)
  end
end
