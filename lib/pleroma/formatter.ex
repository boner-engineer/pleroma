# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Formatter do
  alias Pleroma.Emoji
  alias Pleroma.HTML
  alias Pleroma.User
  alias Pleroma.Web.MediaProxy

  @markdown_characters_regex ~r/(`|\*|_|{|}|[|]|\(|\)|#|\+|-|\.|!)/
  @link_regex ~r{((?:http(s)?:\/\/)?[\w.-]+(?:\.[\w\.-]+)+[\w\-\._~%:/?#[\]@!\$&'\(\)\*\+,;=.]+)|[0-9a-z+\-\.]+:[0-9a-z$-_.+!*'(),]+}ui

  @auto_linker_config hashtag: true,
                      hashtag_handler: &Pleroma.Formatter.hashtag_handler/4,
                      mention: true,
                      mention_handler: &Pleroma.Formatter.mention_handler/4

  def mention_handler("@" <> nickname, buffer, opts, acc) do
    case User.get_cached_by_nickname(nickname) do
      %User{id: id} = user ->
        ap_id = get_ap_id(user)
        nickname_text = get_nickname_text(nickname, opts) |> maybe_escape(opts)

        link =
          "<span class='h-card'><a data-user='#{id}' class='u-url mention' href='#{ap_id}'>@<span>#{
            nickname_text
          }</span></a></span>"

        {link, %{acc | mentions: MapSet.put(acc.mentions, {"@" <> nickname, user})}}

      _ ->
        {buffer, acc}
    end
  end

  def hashtag_handler("#" <> tag = tag_text, _buffer, _opts, acc) do
    tag = String.downcase(tag)
    url = "#{Pleroma.Web.base_url()}/tag/#{tag}"
    link = "<a class='hashtag' data-tag='#{tag}' href='#{url}' rel='tag'>#{tag_text}</a>"

    {link, %{acc | tags: MapSet.put(acc.tags, {tag_text, tag})}}
  end

  @doc """
  Parses a text and replace plain text links with HTML. Returns a tuple with a result text, mentions, and hashtags.
  """
  @spec linkify(String.t(), keyword()) ::
          {String.t(), [{String.t(), User.t()}], [{String.t(), String.t()}]}
  def linkify(text, options \\ []) do
    options = options ++ @auto_linker_config
    acc = %{mentions: MapSet.new(), tags: MapSet.new()}
    {text, %{mentions: mentions, tags: tags}} = AutoLinker.link_map(text, acc, options)

    {text, MapSet.to_list(mentions), MapSet.to_list(tags)}
  end

  def emojify(text) do
    emojify(text, Emoji.get_all())
  end

  def emojify(text, nil), do: text

  def emojify(text, emoji, strip \\ false) do
    Enum.reduce(emoji, text, fn {emoji, file}, text ->
      emoji = HTML.strip_tags(emoji)
      file = HTML.strip_tags(file)

      html =
        if not strip do
          "<img height='32px' width='32px' alt='#{emoji}' title='#{emoji}' src='#{
            MediaProxy.url(file)
          }' />"
        else
          ""
        end

      String.replace(text, ":#{emoji}:", html) |> HTML.filter_tags()
    end)
  end

  def demojify(text) do
    emojify(text, Emoji.get_all(), true)
  end

  def demojify(text, nil), do: text

  def get_emoji(text) when is_binary(text) do
    Enum.filter(Emoji.get_all(), fn {emoji, _} -> String.contains?(text, ":#{emoji}:") end)
  end

  def get_emoji(_), do: []

  def html_escape({text, mentions, hashtags}, type) do
    {html_escape(text, type), mentions, hashtags}
  end

  def html_escape(text, "text/html") do
    HTML.filter_tags(text)
  end

  def html_escape(text, "text/plain") do
    Regex.split(@link_regex, text, include_captures: true)
    |> Enum.map_every(2, fn chunk ->
      {:safe, part} = Phoenix.HTML.html_escape(chunk)
      part
    end)
    |> Enum.join("")
  end

  def truncate(text, max_length \\ 200, omission \\ "...") do
    # Remove trailing whitespace
    text = Regex.replace(~r/([^ \t\r\n])([ \t]+$)/u, text, "\\g{1}")

    if String.length(text) < max_length do
      text
    else
      length_with_omission = max_length - String.length(omission)
      String.slice(text, 0, length_with_omission) <> omission
    end
  end

  defp get_ap_id(%User{info: %{source_data: %{"url" => url}}}) when is_binary(url), do: url
  defp get_ap_id(%User{ap_id: ap_id}), do: ap_id

  defp get_nickname_text(nickname, %{mentions_format: :full}), do: User.full_nickname(nickname)
  defp get_nickname_text(nickname, _), do: User.local_nickname(nickname)

  defp maybe_escape(str, %{mentions_escape: true}) do
    String.replace(str, @markdown_characters_regex, "\\\\\\1")
  end

  defp maybe_escape(str, _), do: str
end
