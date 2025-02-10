defmodule LlmInterface.LanguageModel do
  @chat_completions_url "http://192.168.18.37:1234/v1/chat/completions"

  def chat_completion(request) do
    Req.post(@chat_completions_url,
      json: set_stream(request, false)
    )
  end

  def chat_completion(request, callback) do
    Req.post(@chat_completions_url,
      json: set_stream(request, true),
      into: fn {:data, data}, acc ->
        Enum.each(parse(data), callback)
        {:cont, acc}
      end
    )
  end

  defp set_stream(request, value) do
    request
    |> Map.drop([:stream, "stream"])
    |> Map.put(:stream, value)
  end

  defp parse(chunk) do
    chunk
    |> String.split("data: ")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&decode/1)
    |> Enum.reject(&is_nil/1)
  end

  defp decode(""), do: nil
  defp decode("[DONE]"), do: nil
  defp decode(data), do: Jason.decode!(data)
end
