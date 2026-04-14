import Config

# Configure ReqAnthropic. All options are optional and can also be passed
# at the call site as a keyword option to any resource function.
#
#     config :req_anthropic,
#       api_key: System.get_env("ANTHROPIC_API_KEY"),
#       base_url: "https://api.anthropic.com",
#       anthropic_version: "2023-06-01",
#       beta: [],
#       models_cache_ttl: :timer.hours(1)
#
# At runtime, an :api_key option passed directly to a function takes
# precedence over the application environment, which in turn takes
# precedence over the ANTHROPIC_API_KEY environment variable.

if File.exists?(Path.expand("#{config_env()}.exs", __DIR__)) do
  import_config "#{config_env()}.exs"
end
