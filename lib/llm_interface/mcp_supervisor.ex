defmodule LlmInterface.MCPSupervisor do
  @moduledoc """
  Supervisor for MCP clients and related processes.

  This supervisor ensures that:
  1. All MCP transports start first
  2. All MCP clients start after their transports
  3. The McpTools registry starts after all clients are ready

  Uses a rest_for_one strategy to ensure proper ordering and dependencies.
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    mcp_client_name = Keyword.fetch!(opts, :mcp_client_name)
    google_maps_client_name = Keyword.fetch!(opts, :google_maps_client_name)

    children = [
      # Group 1: Transports
      Supervisor.child_spec(
        {Hermes.Transport.STDIO,
         [
           name: LlmInterfaceWeb.MCPTransport,
           client: mcp_client_name,
           command: "npx",
           args: ["-y", "hexdocs-mcp@0.2.0"]
         ]},
        id: :hexdocs_mcp_transport
      ),
      Supervisor.child_spec(
        {Hermes.Transport.STDIO,
         [
           name: LlmInterfaceWeb.GoogleMapsMCPTransport,
           client: google_maps_client_name,
           command: "npx",
           args: ["-y", "@modelcontextprotocol/server-google-maps"],
           env: %{
             "GOOGLE_MAPS_API_KEY" => System.get_env("GOOGLE_MAPS_API_KEY")
           }
         ]},
        id: :google_maps_mcp_transport
      ),

      # Group 2: Clients - start after transports
      Supervisor.child_spec(
        {Hermes.Client,
         [
           name: mcp_client_name,
           transport: [layer: Hermes.Transport.STDIO, name: LlmInterfaceWeb.MCPTransport],
           client_info: %{
             "name" => "LlmInterfaceWeb",
             "version" => "1.0.0"
           },
           capabilities: %{
             "tools" => %{},
             "hexdocs" => %{}
           }
         ]},
        id: :hexdocs_mcp_client
      ),
      Supervisor.child_spec(
        {Hermes.Client,
         [
           name: google_maps_client_name,
           transport: [
             layer: Hermes.Transport.STDIO,
             name: LlmInterfaceWeb.GoogleMapsMCPTransport
           ],
           client_info: %{
             "name" => "LlmInterfaceWeb",
             "version" => "1.0.0"
           },
           capabilities: %{
             "tools" => %{},
             "google-maps" => %{}
           }
         ]},
        id: :google_maps_mcp_client
      ),

      # Group 3: Tools Registry - starts after all clients are ready
      {LlmInterface.McpTools, []}
    ]

    # Use rest_for_one strategy - if a process fails, all processes started after it are restarted
    # This ensures dependency order is maintained during restarts
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
