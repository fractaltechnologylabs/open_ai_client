import Config

config :open_ai_client,
       :base_url,
       System.get_env("OPENAI_BASE_URL") || "https://api.openai.com/v1"

config :open_ai_client,
       :openai_api_key,
       System.get_env("OPENAI_API_KEY") || raise("OPENAI_API_KEY is not set")

config :open_ai_client, :receive_timeout, System.get_env("OPENAI_RECEIVE_TIMEOUT") || 600_000
