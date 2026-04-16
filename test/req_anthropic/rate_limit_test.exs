defmodule ReqAnthropic.RateLimitTest do
  use ExUnit.Case, async: true

  alias ReqAnthropic.RateLimit

  describe "from_response/1" do
    test "parses all rate-limit headers when present" do
      resp = %Req.Response{
        status: 200,
        headers: %{
          "anthropic-ratelimit-requests-remaining" => ["98"],
          "anthropic-ratelimit-tokens-remaining" => ["49500"],
          "retry-after" => ["30"]
        },
        body: %{}
      }

      assert %RateLimit{
               requests_remaining: 98,
               tokens_remaining: 49500,
               retry_after: 30
             } = RateLimit.from_response(resp)
    end

    test "returns nil for missing headers" do
      resp = %Req.Response{
        status: 200,
        headers: %{
          "anthropic-ratelimit-requests-remaining" => ["10"]
        },
        body: %{}
      }

      rl = RateLimit.from_response(resp)
      assert rl.requests_remaining == 10
      assert rl.tokens_remaining == nil
      assert rl.retry_after == nil
    end

    test "returns all nils when no rate-limit headers present" do
      resp = %Req.Response{status: 200, headers: %{}, body: %{}}

      assert %RateLimit{
               requests_remaining: nil,
               tokens_remaining: nil,
               retry_after: nil
             } = RateLimit.from_response(resp)
    end

    test "handles non-numeric header values gracefully" do
      resp = %Req.Response{
        status: 200,
        headers: %{
          "anthropic-ratelimit-requests-remaining" => ["not-a-number"],
          "anthropic-ratelimit-tokens-remaining" => ["42"]
        },
        body: %{}
      }

      rl = RateLimit.from_response(resp)
      assert rl.requests_remaining == nil
      assert rl.tokens_remaining == 42
    end
  end
end
