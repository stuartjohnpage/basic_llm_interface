defmodule LlmInterface.Repo do
  use Ecto.Repo,
    otp_app: :llm_interface,
    adapter: Ecto.Adapters.Postgres
end
