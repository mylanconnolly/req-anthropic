defmodule ReqAnthropic.MessagesTest do
  use ExUnit.Case, async: false

  alias ReqAnthropic.Messages

  setup do
    Application.put_env(:req_anthropic, :api_key, "test-key")
    Application.put_env(:req_anthropic, :plug, {Req.Test, ReqAnthropic})
    :ok
  end

  describe "create/1" do
    test "POSTs JSON to /v1/messages and returns the decoded body" do
      Req.Test.stub(ReqAnthropic, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/messages"
        assert conn.body_params["model"] == "claude-haiku-4-5"
        assert conn.body_params["max_tokens"] == 16

        Req.Test.json(conn, %{
          "id" => "msg_1",
          "role" => "assistant",
          "content" => [%{"type" => "text", "text" => "pong"}]
        })
      end)

      assert {:ok, body} =
               Messages.create(
                 model: "claude-haiku-4-5",
                 max_tokens: 16,
                 messages: [%{role: "user", content: "ping"}]
               )

      assert body["id"] == "msg_1"
      assert [%{"text" => "pong"}] = body["content"]
    end

    test "returns {:error, %Error{}} for non-2xx" do
      Req.Test.stub(ReqAnthropic, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          429,
          Jason.encode!(%{
            "type" => "error",
            "error" => %{"type" => "rate_limit_error", "message" => "slow down"}
          })
        )
      end)

      assert {:error, %ReqAnthropic.Error{type: "rate_limit_error", status: 429}} =
               Messages.create(model: "x", max_tokens: 1, messages: [])
    end
  end

  describe "stream/1" do
    test "yields parsed events and reassembles via collect/1" do
      sse = """
      event: message_start
      data: {"type":"message_start","message":{"id":"m1","role":"assistant","content":[],"usage":{"input_tokens":3,"output_tokens":0}}}

      event: content_block_start
      data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" there"}}

      event: content_block_stop
      data: {"type":"content_block_stop","index":0}

      event: message_delta
      data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":2}}

      event: message_stop
      data: {"type":"message_stop"}

      """

      Req.Test.stub(ReqAnthropic, fn conn ->
        assert conn.body_params["stream"] == true

        conn
        |> Plug.Conn.put_resp_content_type("text/event-stream")
        |> Plug.Conn.send_resp(200, sse)
      end)

      assert {:ok, stream} =
               Messages.stream(
                 model: "claude-haiku-4-5",
                 max_tokens: 16,
                 messages: [%{role: "user", content: "ping"}]
               )

      events = Enum.to_list(stream)
      types = Enum.map(events, & &1["type"])

      assert "message_start" in types
      assert "message_stop" in types

      text =
        events
        |> ReqAnthropic.Messages.text_deltas()
        |> Enum.join()

      assert text == "Hi there"
    end

    test "text_deltas only yields text" do
      events = [
        %{"type" => "message_start"},
        %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "text_delta", "text" => "a"}
        },
        %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "input_json_delta", "partial_json" => "{}"}
        },
        %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "text_delta", "text" => "b"}
        }
      ]

      assert ["a", "b"] = events |> Messages.text_deltas() |> Enum.to_list()
    end

    test "collect reassembles deltas back into a final message" do
      events = [
        %{
          "type" => "message_start",
          "message" => %{
            "id" => "m1",
            "role" => "assistant",
            "content" => [],
            "usage" => %{"input_tokens" => 5}
          }
        },
        %{
          "type" => "content_block_start",
          "index" => 0,
          "content_block" => %{"type" => "text", "text" => ""}
        },
        %{
          "type" => "content_block_delta",
          "index" => 0,
          "delta" => %{"type" => "text_delta", "text" => "Hello"}
        },
        %{
          "type" => "content_block_delta",
          "index" => 0,
          "delta" => %{"type" => "text_delta", "text" => " world"}
        },
        %{"type" => "content_block_stop", "index" => 0},
        %{
          "type" => "message_delta",
          "delta" => %{"stop_reason" => "end_turn"},
          "usage" => %{"output_tokens" => 2}
        },
        %{"type" => "message_stop"}
      ]

      assert {:ok, message} = Messages.collect(events)
      assert message["id"] == "m1"
      assert message["stop_reason"] == "end_turn"
      assert [%{"type" => "text", "text" => "Hello world"}] = message["content"]
      assert message["usage"]["input_tokens"] == 5
      assert message["usage"]["output_tokens"] == 2
    end
  end

  describe "run/1" do
    test "executes tool calls and loops until final response" do
      call_count = :counters.new(1, [:atomics])

      Req.Test.stub(ReqAnthropic, fn conn ->
        :counters.add(call_count, 1, 1)
        n = :counters.get(call_count, 1)

        if n == 1 do
          # First call: model requests tool use
          Req.Test.json(conn, %{
            "id" => "msg_1",
            "role" => "assistant",
            "stop_reason" => "tool_use",
            "content" => [
              %{
                "type" => "tool_use",
                "id" => "toolu_1",
                "name" => "get_weather",
                "input" => %{"city" => "Tokyo"}
              }
            ]
          })
        else
          # Second call: model produces final text
          # Verify the tool result was sent back
          messages = conn.body_params["messages"]
          last_msg = List.last(messages)
          assert last_msg["role"] == "user"
          [tool_result] = last_msg["content"]
          assert tool_result["type"] == "tool_result"
          assert tool_result["tool_use_id"] == "toolu_1"
          assert tool_result["content"] == "72°F and sunny in Tokyo"

          Req.Test.json(conn, %{
            "id" => "msg_2",
            "role" => "assistant",
            "stop_reason" => "end_turn",
            "content" => [%{"type" => "text", "text" => "It's 72°F and sunny in Tokyo."}]
          })
        end
      end)

      tools = [
        ReqAnthropic.Tools.custom(
          name: "get_weather",
          description: "Look up weather",
          input_schema: %{type: "object", properties: %{city: %{type: "string"}}},
          function: fn %{"city" => city} -> "72°F and sunny in #{city}" end
        )
      ]

      assert {:ok, message} =
               Messages.run(
                 model: "claude-haiku-4-5",
                 max_tokens: 256,
                 tools: tools,
                 messages: [%{role: "user", content: "What's the weather in Tokyo?"}]
               )

      assert message["stop_reason"] == "end_turn"
      assert [%{"text" => "It's 72°F and sunny in Tokyo."}] = message["content"]
      assert :counters.get(call_count, 1) == 2
    end

    test "returns error when max_rounds exceeded" do
      Req.Test.stub(ReqAnthropic, fn conn ->
        Req.Test.json(conn, %{
          "id" => "msg_1",
          "role" => "assistant",
          "stop_reason" => "tool_use",
          "content" => [
            %{"type" => "tool_use", "id" => "toolu_1", "name" => "ping", "input" => %{}}
          ]
        })
      end)

      tools = [
        ReqAnthropic.Tools.custom(
          name: "ping",
          description: "ping",
          input_schema: %{type: "object"},
          function: fn _ -> "pong" end
        )
      ]

      assert {:error, %ReqAnthropic.Error{type: "max_rounds_exceeded"}} =
               Messages.run(
                 model: "claude-haiku-4-5",
                 max_tokens: 16,
                 tools: tools,
                 messages: [%{role: "user", content: "ping"}],
                 max_rounds: 2
               )
    end

    test "sends error tool_result for tools without a function" do
      call_count = :counters.new(1, [:atomics])

      Req.Test.stub(ReqAnthropic, fn conn ->
        :counters.add(call_count, 1, 1)
        n = :counters.get(call_count, 1)

        if n == 1 do
          Req.Test.json(conn, %{
            "id" => "msg_1",
            "role" => "assistant",
            "stop_reason" => "tool_use",
            "content" => [
              %{
                "type" => "tool_use",
                "id" => "toolu_1",
                "name" => "no_fn",
                "input" => %{}
              }
            ]
          })
        else
          messages = conn.body_params["messages"]
          last_msg = List.last(messages)
          [tool_result] = last_msg["content"]
          assert tool_result["is_error"] == true

          Req.Test.json(conn, %{
            "id" => "msg_2",
            "role" => "assistant",
            "stop_reason" => "end_turn",
            "content" => [%{"type" => "text", "text" => "Sorry, I can't do that."}]
          })
        end
      end)

      tools = [
        ReqAnthropic.Tools.custom(
          name: "no_fn",
          description: "no function",
          input_schema: %{type: "object"}
        )
      ]

      assert {:ok, message} =
               Messages.run(
                 model: "claude-haiku-4-5",
                 max_tokens: 256,
                 tools: tools,
                 messages: [%{role: "user", content: "call no_fn"}]
               )

      assert message["stop_reason"] == "end_turn"
    end

    test "strips __function__ from tools before sending" do
      Req.Test.stub(ReqAnthropic, fn conn ->
        [tool] = conn.body_params["tools"]
        refute Map.has_key?(tool, "__function__")
        refute Map.has_key?(tool, "__beta__")

        Req.Test.json(conn, %{
          "id" => "msg_1",
          "role" => "assistant",
          "stop_reason" => "end_turn",
          "content" => [%{"type" => "text", "text" => "ok"}]
        })
      end)

      tools = [
        ReqAnthropic.Tools.custom(
          name: "x",
          description: "x",
          input_schema: %{type: "object"},
          function: fn _ -> "ok" end
        )
      ]

      assert {:ok, _} =
               Messages.run(
                 model: "claude-haiku-4-5",
                 max_tokens: 16,
                 tools: tools,
                 messages: [%{role: "user", content: "hi"}]
               )
    end
  end

  describe "count_tokens/1" do
    test "POSTs to /v1/messages/count_tokens" do
      Req.Test.stub(ReqAnthropic, fn conn ->
        assert conn.request_path == "/v1/messages/count_tokens"
        Req.Test.json(conn, %{"input_tokens" => 17})
      end)

      assert {:ok, %{"input_tokens" => 17}} =
               Messages.count_tokens(
                 model: "claude-haiku-4-5",
                 messages: [%{role: "user", content: "hi"}]
               )
    end
  end
end
