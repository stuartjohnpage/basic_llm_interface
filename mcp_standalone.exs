# Standalone MCP test
# elixir mcp_standalone.exs

Mix.install([
  {:hermes_mcp, "~> 0.3"}
])

defmodule MCPTest do
  def run do
    # Start the required applications
    Application.ensure_all_started(:hermes_mcp)

    # Create a client registry name
    client_name = MCPTest.Client

    # Set up the transport
    {:ok, _transport_pid} =
      Hermes.Transport.STDIO.start_link(
        name: MCPTest.Transport,
        # Add the client name here
        client: client_name,
        command: "npx",
        args: ["-y", "hexdocs-mcp@0.2.0"]
      )

    # Set up the client
    {:ok, _client_pid} =
      Hermes.Client.start_link(
        name: client_name,
        transport: [
          layer: Hermes.Transport.STDIO,
          name: MCPTest.Transport
        ],
        client_info: %{
          "name" => "Test",
          "version" => "0.1.0"
        },
        capabilities: %{
          "tools" => %{},
          "hexdocs" => %{}
        },
        wait_for_handshake: true,
        handshake_timeout: 10_000
      )

    # Wait a moment for the handshake to complete
    Process.sleep(2000)

    # Test the connection
    IO.puts("===== MCP Connection Test =====")
    IO.puts("Testing connection to MCP server...")

    case Hermes.Client.ping(client_name) do
      :pong ->
        IO.puts("✅ SUCCESS: Connection successful! Received :pong response")
        IO.puts("Your MCP client is properly connected to the server.")

      {:error, reason} ->
        IO.puts("❌ ERROR: Connection failed")
        IO.puts("Reason: #{inspect(reason)}")
        IO.puts("Please check your configuration and make sure the server is running.")
    end

    Hermes.Client.list_tools(client_name) |> IO.inspect()

    IO.puts("================================")

    # Keep the script running for a while to allow for interaction
    Process.sleep(2000)

    # Cleanup
    Hermes.Client.close(client_name)
    Process.sleep(500)
  end
end

MCPTest.run()
