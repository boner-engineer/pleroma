# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.TwitterAPI.UserView do
  use Pleroma.Web, :view
  alias Pleroma.Formatter
  alias Pleroma.HTML
  alias Pleroma.User
  alias Pleroma.Web.CommonAPI.Utils
  alias Pleroma.Web.MediaProxy
  alias Pleroma.Web.TwitterAPI.UserView

  def render("show.json", %{user: user = %User{}} = assigns) do
    render_one(user, Pleroma.Web.TwitterAPI.UserView, "user.json", assigns)
  end

  def render("index.json", %{users: users, for: user}) do
    users
    |> render_many(Pleroma.Web.TwitterAPI.UserView, "user.json", for: user)
    |> Enum.filter(&Enum.any?/1)
  end

  def render("user.json", %{user: user = %User{}} = assigns) do
    if User.visible_for?(user, assigns[:for]),
      do: do_render("user.json", assigns),
      else: %{}
  end

  def render("index_for_admin.json", %{users: users} = opts) do
    users
    |> render_many(UserView, "show_for_admin.json", opts)
  end

  def render("show_for_admin.json", %{user: user}) do
    %{
      "id" => user.id,
      "nickname" => user.nickname,
      "deactivated" => user.info.deactivated
    }
  end

  def render("short.json", %{
        user: %User{
          nickname: nickname,
          id: id,
          ap_id: ap_id,
          name: name
        }
      }) do
    %{
      "fullname" => name,
      "id" => id,
      "ostatus_uri" => ap_id,
      "profile_url" => ap_id,
      "screen_name" => nickname
    }
  end

  defp do_render("user.json", %{user: user = %User{}} = assigns) do
    for_user = assigns[:for]
    image = User.avatar_url(user) |> MediaProxy.url()

    {following, follows_you, statusnet_blocking} =
      if for_user do
        {
          User.following?(for_user, user),
          User.following?(user, for_user),
          User.blocks?(for_user, user)
        }
      else
        {false, false, false}
      end

    user_info = User.get_cached_user_info(user)

    emoji =
      (user.info.source_data["tag"] || [])
      |> Enum.filter(fn %{"type" => t} -> t == "Emoji" end)
      |> Enum.map(fn %{"icon" => %{"url" => url}, "name" => name} ->
        {String.trim(name, ":"), url}
      end)

    # ``fields`` is an array of mastodon profile field, containing ``{"name": "…", "value": "…"}``.
    # For example: [{"name": "Pronoun", "value": "she/her"}, …]
    fields =
      (user.info.source_data["attachment"] || [])
      |> Enum.filter(fn %{"type" => t} -> t == "PropertyValue" end)
      |> Enum.map(fn fields -> Map.take(fields, ["name", "value"]) end)

    data = %{
      "created_at" => user.inserted_at |> Utils.format_naive_asctime(),
      "description" => HTML.strip_tags((user.bio || "") |> String.replace("<br>", "\n")),
      "description_html" => HTML.filter_tags(user.bio, User.html_filter_policy(for_user)),
      "favourites_count" => 0,
      "followers_count" => user_info[:follower_count],
      "following" => following,
      "follows_you" => follows_you,
      "statusnet_blocking" => statusnet_blocking,
      "friends_count" => user_info[:following_count],
      "id" => user.id,
      "name" => user.name || user.nickname,
      "name_html" =>
        if(user.name,
          do: HTML.strip_tags(user.name) |> Formatter.emojify(emoji),
          else: user.nickname
        ),
      "profile_image_url" => image,
      "profile_image_url_https" => image,
      "profile_image_url_profile_size" => image,
      "profile_image_url_original" => image,
      "rights" => %{
        "delete_others_notice" => !!user.info.is_moderator,
        "admin" => !!user.info.is_admin
      },
      "screen_name" => user.nickname,
      "statuses_count" => user_info[:note_count],
      "statusnet_profile_url" => user.ap_id,
      "cover_photo" => User.banner_url(user) |> MediaProxy.url(),
      "background_image" => image_url(user.info.background) |> MediaProxy.url(),
      "is_local" => user.local,
      "locked" => user.info.locked,
      "default_scope" => user.info.default_scope,
      "no_rich_text" => user.info.no_rich_text,
      "hide_followers" => user.info.hide_followers,
      "hide_follows" => user.info.hide_follows,
      "fields" => fields,

      # Pleroma extension
      "pleroma" =>
        %{
          "confirmation_pending" => user_info.confirmation_pending,
          "tags" => user.tags
        }
        |> maybe_with_activation_status(user, for_user)
        |> maybe_with_follow_request_count(user, for_user)
    }

    data =
      if(user.info.is_admin || user.info.is_moderator,
        do: maybe_with_role(data, user, for_user),
        else: data
      )

    if assigns[:token] do
      Map.put(data, "token", token_string(assigns[:token]))
    else
      data
    end
  end

  defp maybe_with_activation_status(data, user, %User{info: %{is_admin: true}}) do
    Map.put(data, "deactivated", user.info.deactivated)
  end

  defp maybe_with_activation_status(data, _, _), do: data

  defp maybe_with_follow_request_count(data, %User{id: id, info: %{locked: true}} = user, %User{
         id: id
       }) do
    Map.put(data, "follow_request_count", user.info.follow_request_count)
  end

  defp maybe_with_follow_request_count(data, _, _), do: data

  defp maybe_with_role(data, %User{id: id} = user, %User{id: id}) do
    Map.merge(data, %{"role" => role(user), "show_role" => user.info.show_role})
  end

  defp maybe_with_role(data, %User{info: %{show_role: true}} = user, _user) do
    Map.merge(data, %{"role" => role(user)})
  end

  defp maybe_with_role(data, _, _), do: data

  defp role(%User{info: %{:is_admin => true}}), do: "admin"
  defp role(%User{info: %{:is_moderator => true}}), do: "moderator"
  defp role(_), do: "member"

  defp image_url(%{"url" => [%{"href" => href} | _]}), do: href
  defp image_url(_), do: nil

  defp token_string(%Pleroma.Web.OAuth.Token{token: token_str}), do: token_str
  defp token_string(token), do: token
end
