import Config

config :req_anthropic,
  api_key: "test-key",
  plug: {Req.Test, ReqAnthropic}
