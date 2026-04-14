defmodule ReqAnthropic.SSETest do
  use ExUnit.Case, async: true

  alias ReqAnthropic.SSE

  test "decodes a single complete event" do
    chunks = [
      "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"m1\"}}\n\n"
    ]

    assert [event] = chunks |> SSE.parse_stream() |> Enum.to_list()
    assert event["type"] == "message_start"
    assert event["message"] == %{"id" => "m1"}
  end

  test "joins events split across chunk boundaries" do
    chunks = [
      "event: content_block_delta\nda",
      "ta: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n",
      "\nevent: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\" world\"}}\n\n"
    ]

    events = chunks |> SSE.parse_stream() |> Enum.to_list()
    assert length(events) == 2
    assert Enum.map(events, & &1["delta"]["text"]) == ["Hello", " world"]
  end

  test "yields ping events without a data line" do
    chunks = ["event: ping\n\n"]

    assert [%{"type" => "ping"}] = chunks |> SSE.parse_stream() |> Enum.to_list()
  end

  test "skips comment lines and unknown fields" do
    chunks = [": keep-alive\nid: 5\nevent: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"]

    assert [%{"type" => "message_stop"}] = chunks |> SSE.parse_stream() |> Enum.to_list()
  end

  test "wraps malformed JSON as an error event" do
    chunks = ["event: message_delta\ndata: {not json}\n\n"]

    assert [{:error, %ReqAnthropic.Error{type: "stream_decode_error"}}] =
             chunks |> SSE.parse_stream() |> Enum.to_list()
  end

  test "decodes the full Messages event lifecycle" do
    body = """
    event: message_start
    data: {"type":"message_start","message":{"id":"m1","role":"assistant","content":[],"usage":{"input_tokens":10,"output_tokens":0}}}

    event: content_block_start
    data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"!"}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":0}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":2}}

    event: message_stop
    data: {"type":"message_stop"}

    """

    events = [body] |> SSE.parse_stream() |> Enum.to_list()
    types = Enum.map(events, & &1["type"])

    assert types == [
             "message_start",
             "content_block_start",
             "content_block_delta",
             "content_block_delta",
             "content_block_stop",
             "message_delta",
             "message_stop"
           ]
  end
end
