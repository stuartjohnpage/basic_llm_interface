defmodule LlmInterfaceWeb.ChatsLive.Index do
  use LlmInterfaceWeb, :live_view

  alias LlmInterfaceWeb.Unsafe
  alias LlmInterface.MCPTools

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:messages, [])
      |> assign(:running, false)
      |> assign(:current_tool_call, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("submit", %{"content" => content}, socket) do
    # Use string keys for message structure
    message = %{"role" => "user", "content" => content}
    updated_messages = [message | socket.assigns.messages]
    MCPTools.refresh_tools()

    # The process id of the current LiveView
    pid = self()

    socket =
      socket
      |> assign(:running, true)
      |> assign(:messages, updated_messages)
      |> assign(:current_tool_call, nil)
      |> start_async(:chat_completion, fn ->
        run_chat_completion(pid, Enum.reverse(updated_messages))
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("stop", _, socket) do
    # Cancel the async task
    socket = cancel_async(socket, :chat_completion)

    # Update the message to indicate it was stopped
    updated_messages =
      case socket.assigns.messages do
        [%{"role" => "assistant", "content" => content} | rest] ->
          [%{"role" => "assistant", "content" => content <> "\n\n*Stopped by user*"} | rest]

        messages ->
          messages
      end

    {:noreply,
     socket
     |> assign(:running, false)
     |> assign(:messages, updated_messages)}
  end

  @impl true
  def handle_async(:chat_completion, _result, socket) do
    {:noreply, assign(socket, :running, false)}
  end

  @impl true
  def handle_info({:chunk, chunk}, socket) do
    updated_socket = process_chunk(chunk, socket)
    {:noreply, updated_socket}
  end

  @impl true
  def handle_info({:error, message}, socket) do
    # Show the error message to the user
    {:noreply,
     socket
     |> put_flash(:error, message)
     |> assign(:loading, false)}
  end

  @impl true
  def handle_info({:tool_call, tool_call}, socket) do
    # Execute the tool call
    result = MCPTools.execute_tool_call(tool_call)

    # Format the content appropriately based on the result type
    content = MCPTools.format_tool_result(result)

    # Create a tool response message using the proper format with string keys
    tool_result_message = %{
      "role" => "tool",
      "content" => content,
      "tool_call_id" => tool_call["id"]
    }

    # Add the tool result to messages
    updated_messages = [tool_result_message | socket.assigns.messages]

    # Continue the conversation with the tool result
    pid = self()

    socket =
      socket
      |> assign(:running, true)
      |> assign(:messages, updated_messages)
      |> assign(:current_tool_call, nil)
      |> start_async(:chat_completion, fn ->
        run_chat_completion(pid, Enum.reverse(updated_messages))
      end)

    {:noreply, socket}
  end

  defp process_chunk(chunk, socket) do
    case chunk do
      # Normal content chunk
      %{"choices" => [%{"delta" => %{"content" => content}}]} ->
        update_message_content(socket, content)

      # Tool call chunk - initial or continuation
      %{"choices" => [%{"delta" => %{"tool_calls" => tool_calls}}]} ->
        process_tool_calls(socket, tool_calls)

      # Finish message for tool call
      %{"choices" => [%{"delta" => %{}, "finish_reason" => "stop"}]} ->
        finalize_tool_call(socket)

      # Ignore other types of chunks
      _ ->
        socket
    end
  end

  defp process_tool_calls(socket, []) do
    socket
  end

  defp process_tool_calls(
         %{assigns: %{current_tool_call: current_tool_call, messages: messages}} = socket,
         tool_calls
       ) do
    # This is called when we receive a tool_call chunk
    # We need to build up the tool call data from the stream
    tool_call = List.first(tool_calls)

    # Initialize or update the current tool call
    updated_tool_call = MCPTools.build_tool_call(current_tool_call, tool_call)

    # Create an assistant message with the tool call info if none exists
    updated_messages = MCPTools.create_tool_call_message(messages, updated_tool_call)

    # Store the current tool call
    socket |> assign(:current_tool_call, updated_tool_call) |> assign(:messages, updated_messages)
  end

  defp finalize_tool_call(%{assigns: %{current_tool_call: nil}} = socket), do: socket

  defp finalize_tool_call(%{assigns: %{current_tool_call: tool_call}} = socket) do
    arguments = parse_tool_arguments(tool_call)
    arguments_json = Jason.encode!(arguments)

    complete_tool_call = %{
      "id" => tool_call["id"],
      "type" => "function",
      "function" => %{
        "name" => tool_call["name"],
        "arguments" => arguments_json
      }
    }

    updated_socket = update_assistant_message(socket, complete_tool_call)

    tool_for_execution = %{
      "id" => tool_call["id"],
      "name" => tool_call["name"],
      "arguments" => arguments
    }

    send(self(), {:tool_call, tool_for_execution})
    assign(updated_socket, :current_tool_call, nil)
  end

  defp parse_tool_arguments(tool_call) do
    try do
      args = Jason.decode!(tool_call["arguments"])
      maybe_convert_numeric_limit(args, tool_call["name"])
    rescue
      _e -> %{}
    end
  end

  defp maybe_convert_numeric_limit(args, "mcp_hexdocs_mcp_search")
       when is_map_key(args, "limit") do
    case args["limit"] do
      limit when is_binary(limit) ->
        {num, _} = Integer.parse(limit)
        Map.put(args, "limit", num)

      _ ->
        args
    end
  end

  defp maybe_convert_numeric_limit(args, _), do: args

  defp update_assistant_message(
         %{assigns: %{messages: [%{"role" => "assistant"} = assistant_message | rest]}} = socket,
         complete_tool_call
       ) do
    updated_message = Map.put(assistant_message, "tool_calls", [complete_tool_call])
    assign(socket, :messages, [updated_message | rest])
  end

  defp update_assistant_message(socket, _complete_tool_call) do
    socket
  end

  defp update_message_content(socket, content) do
    updated_messages =
      case socket.assigns.messages do
        [%{"role" => "assistant", "content" => existing_content} | messages] ->
          if String.contains?(content, "</think>") do
            # Convert think blocks to italics
            new_content =
              (existing_content <> content)
              |> String.replace(~r/<think>(.*?)<\/think>/s, "*\\1*")

            [%{"role" => "assistant", "content" => new_content} | messages]
          else
            [%{"role" => "assistant", "content" => existing_content <> content} | messages]
          end

        messages ->
          [%{"role" => "assistant", "content" => content} | messages]
      end

    assign(socket, :messages, updated_messages)
  end

  defp run_chat_completion(pid, messages) do
    request = %{temperature: 1, messages: messages, tools: MCPTools.get_available_tools()}

    # Use the new chat_completion_stream function with correct parameter format
    case LlmInterface.LanguageModel.chat_completion_stream(
           request,
           fn chunk -> send(pid, {:chunk, chunk}) end,
           timeout: 60_000,
           recv_timeout: 180_000
         ) do
      {:ok, _response} ->
        # Success case - no action needed
        :ok

      {:error, :timeout} ->
        # Send a timeout error message to the LiveView
        send(pid, {:error, "The language model request timed out. Please try again."})

      {:error, reason} ->
        # Send other errors to the LiveView
        send(pid, {:error, "An error occurred: #{inspect(reason)}"})
    end
  end
end
