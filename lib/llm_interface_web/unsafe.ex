defmodule LlmInterfaceWeb.Unsafe do
  @moduledoc """
  A component used to render 'mostly' raw HTML as markdown. It uses
  a custom scrubber for HTMLSanitizeEx, see the MarkdownScrubber module for further
  details.

  IMPORTANT: Use with caution. It should never be passed untrusted user input!

  <Unsafe.raw_markdown content={@document.text} />
  """
  use LlmInterfaceWeb, :html

  alias LlmInterfaceWeb.Html

  def raw_markdown(assigns) do
    ~H"""
    <div class="llm_interface_markdown">
      {raw(safe_html_content(@content))}
    </div>
    """
  end

  defp safe_html_content(content) do
    Html.from_unsafe_markdown(content)
  end
end
