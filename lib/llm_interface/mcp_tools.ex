defmodule LlmInterface.MCPTools do
  @moduledoc """
  Module for handling MCP tool interactions with the language model.
  Maintains a registry of available tools from all MCP clients.
  """
  use GenServer
  require Logger

  # Maximum number of retries for client readiness
  @max_retries 5
  # Delay between retries in milliseconds
  @retry_delay 1000

  # Client API

  @doc """
  Starts the MCP tools registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Execute an MCP tool call and return the result.
  """
  def execute_tool_call(%{"name" => name, "arguments" => arguments}) do
    IO.puts("Executing tool: #{name} with arguments: #{inspect(arguments)}")

    case GenServer.call(__MODULE__, {:get_tool_info, name}) do
      {:ok, client, tool_name} ->
        case Hermes.Client.call_tool(client, tool_name, arguments) do
          {:ok, %Hermes.MCP.Response{result: result, is_error: false}} ->
            result

          {:ok, %Hermes.MCP.Response{result: error_info, is_error: true}} ->
            %{error: "MCP error: #{inspect(error_info)}"}

          {:error, error} ->
            %{error: "Tool execution failed: #{inspect(error)}"}
        end

      :error ->
        %{error: "Unsupported tool: #{name}"}
    end
  end

  @doc """
  Get the available MCP tools for the language model.
  """
  def get_available_tools do
    GenServer.call(__MODULE__, :get_available_tools)
  end

  @doc """
  Refresh available tools by querying all clients again.
  """
  def refresh_tools do
    GenServer.call(__MODULE__, :refresh_tools)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    Process.send_after(self(), {:refresh_tools, 0}, 0)
    clients = Keyword.get(opts, :clients, [])

    {:ok, %{tools: [], tool_map: %{}, clients: clients}}
  end

  @impl true
  def handle_call(:get_available_tools, _from, %{tools: tools} = state) do
    {:reply, tools, state}
  end

  @impl true
  def handle_call({:get_tool_info, tool_name}, _from, %{tool_map: tool_map} = state) do
    case Map.get(tool_map, tool_name) do
      nil -> {:reply, :error, state}
      {client, actual_tool_name} -> {:reply, {:ok, client, actual_tool_name}, state}
    end
  end

  @impl true
  def handle_call(:refresh_tools, _from, state) do
    clients = Map.get(state, :clients)

    {tools, tool_map} = discover_tools(clients)
    {:reply, :ok, %{tools: tools, tool_map: tool_map, clients: clients}}
  end

  @impl true
  def handle_info({:refresh_tools, retry_count}, state) when retry_count < @max_retries do
    clients = Map.get(state, :clients)

    # Try to discover tools with retry logic
    case safe_discover_tools(clients) do
      {:ok, tools, tool_map, clients} ->
        Logger.info("Successfully discovered MCP tools on attempt #{retry_count + 1}")
        {:noreply, %{tools: tools, tool_map: tool_map, clients: clients}}

      {:error, reason} ->
        # Clients may not be ready yet, schedule another retry
        Logger.warning(
          "Failed to discover MCP tools on attempt #{retry_count + 1}: #{inspect(reason)}"
        )

        Process.send_after(self(), {:refresh_tools, retry_count + 1}, @retry_delay)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:refresh_tools, retry_count}, state) do
    Logger.error("Failed to discover MCP tools after #{retry_count} attempts")
    {:noreply, state}
  end

  # Private functions

  defp safe_discover_tools(clients) do
    try do
      {tools, tool_map} = discover_tools(clients)
      {:ok, tools, tool_map, clients}
    rescue
      e -> {:error, e}
    catch
      :exit, reason -> {:error, {:exit, reason}}
    end
  end

  defp discover_tools(clients) do
    # Collect tools from each client
    {all_tools, tool_mappings} =
      Enum.reduce(clients, {[], %{}}, fn {prefix, client}, {tools_acc, map_acc} ->
        client_tools = fetch_client_tools(client, prefix)

        # Create mapping from prefixed tool name to {client, original_tool_name}
        tool_map =
          Enum.reduce(client_tools, %{}, fn tool, acc ->
            %{"function" => %{"name" => prefixed_name}} = tool
            original_name = extract_original_name(prefixed_name, prefix)
            Map.put(acc, prefixed_name, {client, original_name})
          end)

        {tools_acc ++ client_tools, Map.merge(map_acc, tool_map)}
      end)

    {all_tools, tool_mappings}
  end

  defp fetch_client_tools(client, prefix) do
    case Hermes.Client.list_tools(client) do
      {:ok, %Hermes.MCP.Response{result: %{"tools" => tools}, is_error: false}} ->
        # Transform each tool to add prefix to name
        Enum.map(tools, fn tool ->
          # Extract the tool schema (function spec and parameters)
          %{
            "name" => name,
            "inputSchema" => schema
          } = tool

          # Create prefixed JSON schema tool definition for LLM
          %{
            "type" => "function",
            "function" => %{
              "name" => "#{prefix}_#{name}",
              "description" => get_description_from_schema(schema),
              "parameters" => schema
            }
          }
        end)

      {:error, reason} ->
        Logger.warning("Failed to fetch tools from client #{inspect(client)}: #{inspect(reason)}")
        # Return empty list if we can't get tools
        []
    end
  end

  # Extract description from schema if available
  defp get_description_from_schema(%{"description" => description}) when is_binary(description) do
    description
  end

  defp get_description_from_schema(_) do
    "MCP Tool"
  end

  defp extract_original_name(prefixed_name, prefix) do
    String.replace_prefix(prefixed_name, "#{prefix}_", "")
  end

  @doc """
  Create a tool call message for the language model.
  """
  def create_tool_call_message(messages, updated_tool_call) do
    case messages do
      [%{"role" => "assistant", "tool_calls" => _} | _] ->
        # Already have an assistant message with tool calls
        messages

      [%{"role" => "assistant"} = existing | rest] ->
        # Have an assistant message but no tool calls
        updated_message =
          Map.put(existing, "tool_calls", [
            %{
              "id" => updated_tool_call["id"],
              "type" => "function",
              "function" => %{
                "name" => updated_tool_call["name"],
                "arguments" => updated_tool_call["arguments"]
              }
            }
          ])

        [updated_message | rest]

      _ ->
        # No assistant message yet
        new_message = %{
          "role" => "assistant",
          "content" => nil,
          "tool_calls" => [
            %{
              "id" => updated_tool_call["id"],
              "type" => "function",
              "function" => %{
                "name" => updated_tool_call["name"],
                "arguments" => updated_tool_call["arguments"]
              }
            }
          ]
        }

        [new_message | messages]
    end
  end

  @doc """
  Build a tool call from a list of tool calls.
  """
  def build_tool_call(current_tool_call, first_tool_call) do
    case {current_tool_call, first_tool_call} do
      # First tool call with ID and name - initialize it
      {nil, %{"id" => id, "function" => %{"name" => name}}} ->
        %{
          "id" => id,
          "name" => name,
          "arguments" => ""
        }

      # Already initialized tool call - append arguments
      {existing, %{"function" => %{"arguments" => args}}} when not is_nil(existing) ->
        Map.update!(existing, "arguments", fn existing_args -> existing_args <> args end)

      # Keep existing if we can't process this chunk
      _ ->
        current_tool_call
    end
  end

  @doc """
  Format a tool result for display and JSON encoding.
  """
  def format_tool_result(%{"content" => content}) do
    Enum.map_join(content, "", fn item ->
      case item do
        %{"type" => "text", "text" => text} -> text
        _ -> ""
      end
    end)
  end

  def format_tool_result(result) do
    Jason.encode!(result)
  end
end
