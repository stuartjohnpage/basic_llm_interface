defmodule LlmInterfaceWeb.Html do
  @moduledoc """
  Helpers for creating and working with HTML. We use the as_html option so that we do not log
  common errors such as unclosed tags to stderr when converting markdown to HTML. This happens
  frequently when streaming a response that includes a code block from an API ```foo(a, b) ...
  """

  alias HtmlSanitizeEx.Scrubber
  alias LlmInterfaceWeb.Html.MarkdownScrubber

  def from_unsafe_markdown(nil), do: ""

  def from_unsafe_markdown(markdown) do
    case Earmark.as_html(markdown) do
      {:ok, html, []} ->
        Scrubber.scrub(html, MarkdownScrubber)

      {:error, html, _error} ->
        Scrubber.scrub(html, MarkdownScrubber)
    end
  end
end
