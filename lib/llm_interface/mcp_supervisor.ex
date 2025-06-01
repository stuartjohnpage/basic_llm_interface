defmodule LlmInterface.MCPSupervisor do
  @moduledoc """
  Supervisor for MCP clients and related processes.

  This supervisor ensures that:
  1. All MCP transports start first
  2. All MCP clients start after their transports
  3. The MCPTools registry starts after all clients are ready

  Uses a rest_for_one strategy to ensure proper ordering and dependencies.
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @hex_docs_mcp %{
    hexdocs_mcp_client_name: LlmInterface.HexDocsMCPClient,
    hexdocs_mcp_transport_name: LlmInterfaceWeb.HexDocsMCPTransport,
    hexdocs_mcp_prefix: "mcp_hexdocs"
  }

  @google_maps_mcp %{
    google_maps_mcp_client_name: LlmInterface.GoogleMapsMCPClient,
    google_maps_mcp_transport_name: LlmInterfaceWeb.GoogleMapsMCPTransport,
    google_maps_mcp_prefix: "mcp_google_maps"
  }

  @brave_browser_mcp %{
    brave_browser_mcp_client_name: LlmInterface.BraveBrowserMCPClient,
    brave_browser_mcp_transport_name: LlmInterfaceWeb.BraveBrowserMCPTransport,
    brave_browser_mcp_prefix: "mcp_brave_browser"
  }

  @impl true
  def init(_opts) do
    children = [
      # Group 1: Transports
      Supervisor.child_spec(
        {Hermes.Transport.STDIO,
         [
           name: @hex_docs_mcp.hexdocs_mcp_transport_name,
           client: @hex_docs_mcp.hexdocs_mcp_client_name,
           command: "npx",
           args: ["-y", "hexdocs-mcp@0.2.0"]
         ]},
        id: :hexdocs_mcp_transport
      ),
      Supervisor.child_spec(
        {Hermes.Transport.STDIO,
         [
           name: @google_maps_mcp.google_maps_mcp_transport_name,
           client: @google_maps_mcp.google_maps_mcp_client_name,
           command: "docker",
           args: [
             "run",
             "-i",
             "--rm",
             "-e",
             "GOOGLE_MAPS_API_KEY",
             "mcp/google-maps"
           ],
           env: %{
             "GOOGLE_MAPS_API_KEY" => Application.get_env(:llm_interface, :google_maps_api_key)
           },
           capabilities: %{"roots" => %{"listChanged" => true}, "sampling" => %{}}
         ]},
        id: :google_maps_mcp_transport
      ),
      Supervisor.child_spec(
        {Hermes.Transport.STDIO,
         [
           name: @brave_browser_mcp.brave_browser_mcp_transport_name,
           client: @brave_browser_mcp.brave_browser_mcp_client_name,
           command: "docker",
           args: [
             "run",
             "-i",
             "--rm",
             "-e",
             "BRAVE_API_KEY",
             "mcp/brave-search"
           ],
           env: %{
             "BRAVE_API_KEY" => Application.get_env(:llm_interface, :brave_api_key)
           },
           capabilities: %{"roots" => %{"listChanged" => true}, "sampling" => %{}}
         ]},
        id: :brave_browser_mcp_transport
      ),

      # Group 2: Clients - start after transports
      Supervisor.child_spec(
        {Hermes.Client,
         [
           name: @hex_docs_mcp.hexdocs_mcp_client_name,
           transport: [
             layer: Hermes.Transport.STDIO,
             name: @hex_docs_mcp.hexdocs_mcp_transport_name
           ],
           client_info: %{
             "name" => "LlmInterfaceWeb",
             "version" => "1.0.0"
           }
         ]},
        id: :hexdocs_mcp_client
      ),
      Supervisor.child_spec(
        {Hermes.Client,
         [
           name: @google_maps_mcp.google_maps_mcp_client_name,
           transport: [
             layer: Hermes.Transport.STDIO,
             name: @google_maps_mcp.google_maps_mcp_transport_name
           ],
           request_timeout: 60_000,
           client_info: %{
             "name" => "LlmInterfaceWeb",
             "version" => "1.0.0"
           }
         ]},
        id: :google_maps_mcp_client
      ),
      Supervisor.child_spec(
        {Hermes.Client,
         [
           name: @brave_browser_mcp.brave_browser_mcp_client_name,
           transport: [
             layer: Hermes.Transport.STDIO,
             name: @brave_browser_mcp.brave_browser_mcp_transport_name
           ],
           client_info: %{
             "name" => "LlmInterfaceWeb",
             "version" => "1.0.0"
           }
         ]},
        id: :brave_browser_mcp_client
      ),

      # Group 3: Tools Registry - starts after all clients are ready
      {LlmInterface.MCPTools,
       [
         clients: [
           {@hex_docs_mcp.hexdocs_mcp_prefix, @hex_docs_mcp.hexdocs_mcp_client_name},
           {@google_maps_mcp.google_maps_mcp_prefix,
            @google_maps_mcp.google_maps_mcp_client_name},
           {@brave_browser_mcp.brave_browser_mcp_prefix,
            @brave_browser_mcp.brave_browser_mcp_client_name}
         ]
       ]}
    ]

    # Use rest_for_one strategy - if a process fails, all processes started after it are restarted
    # This ensures dependency order is maintained during restarts
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
