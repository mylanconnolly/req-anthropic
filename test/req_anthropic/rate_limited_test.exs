defmodule ReqAnthropic.RateLimitedTest do
  use ExUnit.Case, async: true

  alias ReqAnthropic.{RateLimit, RateLimited}

  describe "from_response/2" do
    test "builds struct with retry_after promoted from rate_limit" do
      rate_limit = %RateLimit{requests_remaining: 0, tokens_remaining: 100, retry_after: 30}

      resp = %Req.Response{
        status: 429,
        headers: %{
          "request-id" => ["req_abc"]
        },
        body: %{
          "type" => "error",
          "error" => %{"type" => "rate_limit_error", "message" => "slow down"}
        }
      }

      rl = RateLimited.from_response(resp, rate_limit)
      assert rl.retry_after == 30
      assert rl.rate_limit == rate_limit
      assert rl.message == "slow down"
      assert rl.request_id == "req_abc"
      assert rl.raw == resp.body
    end

    test "handles flat error body shape" do
      rate_limit = %RateLimit{retry_after: 5}

      resp = %Req.Response{
        status: 429,
        headers: %{},
        body: %{"type" => "rate_limit_error", "message" => "too fast"}
      }

      assert %RateLimited{message: "too fast"} = RateLimited.from_response(resp, rate_limit)
    end

    test "handles unexpected body shape" do
      rate_limit = %RateLimit{retry_after: 10}
      resp = %Req.Response{status: 429, headers: %{}, body: "plain text"}

      assert %RateLimited{message: nil, retry_after: 10} =
               RateLimited.from_response(resp, rate_limit)
    end
  end

  describe "message/1" do
    test "produces a readable error string" do
      err = %RateLimited{
        retry_after: 30,
        rate_limit: %RateLimit{},
        message: "slow down"
      }

      assert Exception.message(err) == "(rate_limited) slow down retry after 30s"
    end

    test "omits nil parts" do
      err = %RateLimited{retry_after: nil, rate_limit: %RateLimit{}, message: nil}
      assert Exception.message(err) == "(rate_limited)"
    end
  end
end
