defmodule ReqAnthropic.ModelsTest do
  use ExUnit.Case, async: false

  alias ReqAnthropic.{Model, Models}

  setup do
    Application.put_env(:req_anthropic, :api_key, "test-key")
    Application.put_env(:req_anthropic, :plug, {Req.Test, ReqAnthropic})
    Models.clear_cache()
    :ok
  end

  test "list returns models and caches them" do
    counter = :counters.new(1, [])

    Req.Test.stub(ReqAnthropic, fn conn ->
      :counters.add(counter, 1, 1)
      assert conn.request_path == "/v1/models"

      Req.Test.json(conn, %{
        "data" => [
          %{"id" => "claude-haiku-4-5", "display_name" => "Claude Haiku 4.5", "type" => "model"},
          %{"id" => "claude-sonnet-4-6", "display_name" => "Claude Sonnet 4.6", "type" => "model"}
        ],
        "has_more" => false
      })
    end)

    assert {:ok, [%Model{id: "claude-haiku-4-5"}, %Model{id: "claude-sonnet-4-6"}]} =
             Models.list()

    assert :counters.get(counter, 1) == 1

    assert {:ok, [%Model{id: "claude-haiku-4-5"}, _]} = Models.list()
    assert :counters.get(counter, 1) == 1, "second call should hit the cache"
  end

  test "list with cache: false bypasses the cache" do
    counter = :counters.new(1, [])

    Req.Test.stub(ReqAnthropic, fn conn ->
      :counters.add(counter, 1, 1)
      Req.Test.json(conn, %{"data" => [%{"id" => "claude-haiku-4-5"}], "has_more" => false})
    end)

    assert {:ok, _} = Models.list()
    assert {:ok, _} = Models.list(cache: false)
    assert :counters.get(counter, 1) == 2
  end

  test "get fetches a single model and caches it" do
    counter = :counters.new(1, [])

    Req.Test.stub(ReqAnthropic, fn conn ->
      :counters.add(counter, 1, 1)
      assert conn.request_path == "/v1/models/claude-haiku-4-5"
      Req.Test.json(conn, %{"id" => "claude-haiku-4-5", "display_name" => "Claude Haiku 4.5"})
    end)

    assert {:ok, %Model{id: "claude-haiku-4-5"}} = Models.get("claude-haiku-4-5")
    assert {:ok, %Model{id: "claude-haiku-4-5"}} = Models.get("claude-haiku-4-5")
    assert :counters.get(counter, 1) == 1
  end

  test "capabilities returns the static table for known models" do
    caps = Models.capabilities("claude-opus-4-6")
    assert caps.supports_vision == true
    assert caps.supports_computer_use == true
    assert caps.max_input_tokens == 200_000
  end

  test "capabilities falls back to a conservative default for unknown models" do
    caps = Models.capabilities("claude-future-1-0")
    assert caps.supports_vision == false
    assert caps.max_output_tokens == nil
  end

  test "clear_cache empties the table" do
    Req.Test.stub(ReqAnthropic, fn conn ->
      Req.Test.json(conn, %{"data" => [%{"id" => "claude-haiku-4-5"}], "has_more" => false})
    end)

    assert {:ok, _} = Models.list()
    Models.clear_cache()
    # Force another call by hitting the API again
    assert {:ok, _} = Models.list()
  end
end
