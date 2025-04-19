defmodule LlmInterface.LanguageModel do
  @moduledoc """
  Handles communication with the language model API.
  Provides functionality for streaming chat completions.
  """

  @chat_completions_url Application.compile_env(
                          :llm_interface,
                          :chat_completions_url,
                          "http://127.0.0.1:1234/v1/chat/completions"
                        )
  @default_timeout Application.compile_env(:llm_interface, :timeout, 60_000)
  @default_recv_timeout Application.compile_env(:llm_interface, :recv_timeout, 240_000)

  @doc """
  Performs a streaming chat completion request.

  Each chunk is passed to the provided callback function.
  Returns `{:ok, response}` or `{:error, reason}`.

  ## Options

  * `:timeout` - Initial connection timeout in milliseconds (default: 60,000 ms)
  * `:recv_timeout` - Streaming receive timeout in milliseconds (default: 240,000 ms)
  """
  @spec chat_completion_stream(map(), function(), keyword()) :: {:ok, map()} | {:error, any()}
  def chat_completion_stream(request, callback, opts \\ []) when is_function(callback, 1) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    recv_timeout = Keyword.get(opts, :recv_timeout, @default_recv_timeout)

    do_streaming_completion(request, callback, timeout, recv_timeout)
  end

  defp do_streaming_completion(request, callback, timeout, recv_timeout) do
    req_options = [
      json: Map.put(request, :stream, true),
      connect_options: [timeout: timeout],
      receive_timeout: recv_timeout,
      into: fn {:data, data}, acc ->
        data
        |> parse()
        |> Enum.each(callback)

        {:cont, acc}
      end
    ]

    case Req.post(@chat_completions_url, req_options) do
      {:ok, %{status: status} = response} when status >= 200 and status < 300 ->
        {:ok, response.body}

      {:ok, response} ->
        require Logger

        Logger.error(
          "Streaming request failed with status #{response.status}: #{inspect(response.body)}"
        )

        {:error, {:http_error, response.status, response.body}}

      {:error, %{reason: :timeout}} ->
        require Logger
        Logger.error("Streaming request timed out")
        {:error, :timeout}

      {:error, reason} ->
        require Logger
        Logger.error("Streaming request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Parses a chunk of streaming data into individual JSON objects.
  @spec parse(binary()) :: [map()]
  defp parse(chunk) do
    chunk
    |> String.split("data: ")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&decode/1)
    |> Enum.reject(&is_nil/1)
  end

  # Decodes a single chunk of data into a map.
  @spec decode(binary()) :: map() | nil
  defp decode(""), do: nil
  defp decode("[DONE]"), do: nil

  defp decode(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> decoded
      {:error, _} -> nil
    end
  end
end
