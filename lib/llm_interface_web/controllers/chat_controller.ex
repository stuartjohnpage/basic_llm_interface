defmodule MyAppWeb.ChatController do
  use LlmInterfaceWeb, :controller

  @nd_json_content_type "application/x-ndjson"

  def stream(conn, %{"request" => request}) do
    conn =
      conn
      |> put_resp_content_type(@nd_json_content_type)
      |> send_chunked(200)

    result =
      LlmInterface.LanguageModel.chat_completion_stream(
        request,
        fn data ->
          json = Jason.encode!(data)
          chunk(conn, json)
          chunk(conn, "\n")
        end,
        timeout: 60_000,
        recv_timeout: 180_000
      )

    case result do
      {:error, reason} ->
        # Send an error message in the stream
        error_json = Jason.encode!(%{error: inspect(reason)})
        chunk(conn, error_json)

      _ ->
        :ok
    end

    conn
  end
end
