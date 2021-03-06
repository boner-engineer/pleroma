# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.TwitterAPI.TwitterAPI do
  alias Pleroma.UserInviteToken
  alias Pleroma.User
  alias Pleroma.Activity
  alias Pleroma.Repo
  alias Pleroma.Object
  alias Pleroma.UserEmail
  alias Pleroma.Mailer
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.TwitterAPI.UserView
  alias Pleroma.Web.CommonAPI

  import Ecto.Query

  def create_status(%User{} = user, %{"status" => _} = data) do
    CommonAPI.post(user, data)
  end

  def delete(%User{} = user, id) do
    with %Activity{data: %{"type" => _type}} <- Repo.get(Activity, id),
         {:ok, activity} <- CommonAPI.delete(id, user) do
      {:ok, activity}
    end
  end

  def follow(%User{} = follower, params) do
    with {:ok, %User{} = followed} <- get_user(params),
         {:ok, follower} <- User.maybe_direct_follow(follower, followed),
         {:ok, activity} <- ActivityPub.follow(follower, followed),
         {:ok, follower, followed} <-
           User.wait_and_refresh(
             Pleroma.Config.get([:activitypub, :follow_handshake_timeout]),
             follower,
             followed
           ) do
      {:ok, follower, followed, activity}
    else
      err -> err
    end
  end

  def unfollow(%User{} = follower, params) do
    with {:ok, %User{} = unfollowed} <- get_user(params),
         {:ok, follower, _follow_activity} <- User.unfollow(follower, unfollowed),
         {:ok, _activity} <- ActivityPub.unfollow(follower, unfollowed) do
      {:ok, follower, unfollowed}
    else
      err -> err
    end
  end

  def block(%User{} = blocker, params) do
    with {:ok, %User{} = blocked} <- get_user(params),
         {:ok, blocker} <- User.block(blocker, blocked),
         {:ok, _activity} <- ActivityPub.block(blocker, blocked) do
      {:ok, blocker, blocked}
    else
      err -> err
    end
  end

  def unblock(%User{} = blocker, params) do
    with {:ok, %User{} = blocked} <- get_user(params),
         {:ok, blocker} <- User.unblock(blocker, blocked),
         {:ok, _activity} <- ActivityPub.unblock(blocker, blocked) do
      {:ok, blocker, blocked}
    else
      err -> err
    end
  end

  def repeat(%User{} = user, ap_id_or_id) do
    with {:ok, _announce, %{data: %{"id" => id}}} <- CommonAPI.repeat(ap_id_or_id, user),
         %Activity{} = activity <- Activity.get_create_by_object_ap_id(id) do
      {:ok, activity}
    end
  end

  def unrepeat(%User{} = user, ap_id_or_id) do
    with {:ok, _unannounce, %{data: %{"id" => id}}} <- CommonAPI.unrepeat(ap_id_or_id, user),
         %Activity{} = activity <- Activity.get_create_by_object_ap_id(id) do
      {:ok, activity}
    end
  end

  def pin(%User{} = user, ap_id_or_id) do
    CommonAPI.pin(ap_id_or_id, user)
  end

  def unpin(%User{} = user, ap_id_or_id) do
    CommonAPI.unpin(ap_id_or_id, user)
  end

  def fav(%User{} = user, ap_id_or_id) do
    with {:ok, _fav, %{data: %{"id" => id}}} <- CommonAPI.favorite(ap_id_or_id, user),
         %Activity{} = activity <- Activity.get_create_by_object_ap_id(id) do
      {:ok, activity}
    end
  end

  def unfav(%User{} = user, ap_id_or_id) do
    with {:ok, _unfav, _fav, %{data: %{"id" => id}}} <- CommonAPI.unfavorite(ap_id_or_id, user),
         %Activity{} = activity <- Activity.get_create_by_object_ap_id(id) do
      {:ok, activity}
    end
  end

  def upload(%Plug.Upload{} = file, %User{} = user, format \\ "xml") do
    {:ok, object} = ActivityPub.upload(file, actor: User.ap_id(user))

    url = List.first(object.data["url"])
    href = url["href"]
    type = url["mediaType"]

    case format do
      "xml" ->
        # Fake this as good as possible...
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <rsp stat="ok" xmlns:atom="http://www.w3.org/2005/Atom">
        <mediaid>#{object.id}</mediaid>
        <media_id>#{object.id}</media_id>
        <media_id_string>#{object.id}</media_id_string>
        <media_url>#{href}</media_url>
        <mediaurl>#{href}</mediaurl>
        <atom:link rel="enclosure" href="#{href}" type="#{type}"></atom:link>
        </rsp>
        """

      "json" ->
        %{
          media_id: object.id,
          media_id_string: "#{object.id}}",
          media_url: href,
          size: 0
        }
        |> Jason.encode!()
    end
  end

  def register_user(params) do
    tokenString = params["token"]

    params = %{
      nickname: params["nickname"],
      name: params["fullname"],
      bio: User.parse_bio(params["bio"]),
      email: params["email"],
      password: params["password"],
      password_confirmation: params["confirm"],
      captcha_solution: params["captcha_solution"],
      captcha_token: params["captcha_token"],
      captcha_answer_data: params["captcha_answer_data"]
    }

    captcha_enabled = Pleroma.Config.get([Pleroma.Captcha, :enabled])
    # true if captcha is disabled or enabled and valid, false otherwise
    captcha_ok =
      if !captcha_enabled do
        :ok
      else
        Pleroma.Captcha.validate(
          params[:captcha_token],
          params[:captcha_solution],
          params[:captcha_answer_data]
        )
      end

    # Captcha invalid
    if captcha_ok != :ok do
      {:error, error} = captcha_ok
      # I have no idea how this error handling works
      {:error, %{error: Jason.encode!(%{captcha: [error]})}}
    else
      registrations_open = Pleroma.Config.get([:instance, :registrations_open])

      # no need to query DB if registration is open
      token =
        unless registrations_open || is_nil(tokenString) do
          Repo.get_by(UserInviteToken, %{token: tokenString})
        end

      cond do
        registrations_open || (!is_nil(token) && !token.used) ->
          changeset = User.register_changeset(%User{}, params)

          with {:ok, user} <- User.register(changeset) do
            !registrations_open && UserInviteToken.mark_as_used(token.token)

            {:ok, user}
          else
            {:error, changeset} ->
              errors =
                Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
                |> Jason.encode!()

              {:error, %{error: errors}}
          end

        !registrations_open && is_nil(token) ->
          {:error, "Invalid token"}

        !registrations_open && token.used ->
          {:error, "Expired token"}
      end
    end
  end

  def password_reset(nickname_or_email) do
    with true <- is_binary(nickname_or_email),
         %User{local: true} = user <- User.get_by_nickname_or_email(nickname_or_email),
         {:ok, token_record} <- Pleroma.PasswordResetToken.create_token(user) do
      user
      |> UserEmail.password_reset_email(token_record.token)
      |> Mailer.deliver_async()
    else
      false ->
        {:error, "bad user identifier"}

      %User{local: false} ->
        {:error, "remote user"}

      nil ->
        {:error, "unknown user"}
    end
  end

  def get_by_id_or_nickname(id_or_nickname) do
    if !is_integer(id_or_nickname) && :error == Integer.parse(id_or_nickname) do
      Repo.get_by(User, nickname: id_or_nickname)
    else
      Repo.get(User, id_or_nickname)
    end
  end

  def get_user(user \\ nil, params) do
    case params do
      %{"user_id" => user_id} ->
        case target = get_by_id_or_nickname(user_id) do
          nil ->
            {:error, "No user with such user_id"}

          _ ->
            {:ok, target}
        end

      %{"screen_name" => nickname} ->
        case target = Repo.get_by(User, nickname: nickname) do
          nil ->
            {:error, "No user with such screen_name"}

          _ ->
            {:ok, target}
        end

      _ ->
        if user do
          {:ok, user}
        else
          {:error, "You need to specify screen_name or user_id"}
        end
    end
  end

  defp parse_int(string, default)

  defp parse_int(string, default) when is_binary(string) do
    with {n, _} <- Integer.parse(string) do
      n
    else
      _e -> default
    end
  end

  defp parse_int(_, default), do: default

  def search(_user, %{"q" => query} = params) do
    limit = parse_int(params["rpp"], 20)
    page = parse_int(params["page"], 1)
    offset = (page - 1) * limit

    q =
      from(
        a in Activity,
        where: fragment("?->>'type' = 'Create'", a.data),
        where: "https://www.w3.org/ns/activitystreams#Public" in a.recipients,
        where:
          fragment(
            "to_tsvector('english', ?->'object'->>'content') @@ plainto_tsquery('english', ?)",
            a.data,
            ^query
          ),
        limit: ^limit,
        offset: ^offset,
        # this one isn't indexed so psql won't take the wrong index.
        order_by: [desc: :inserted_at]
      )

    _activities = Repo.all(q)
  end

  # DEPRECATED mostly, context objects are now created at insertion time.
  def context_to_conversation_id(context) do
    with %Object{id: id} <- Object.get_cached_by_ap_id(context) do
      id
    else
      _e ->
        changeset = Object.context_mapping(context)

        case Repo.insert(changeset) do
          {:ok, %{id: id}} ->
            id

          # This should be solved by an upsert, but it seems ecto
          # has problems accessing the constraint inside the jsonb.
          {:error, _} ->
            Object.get_cached_by_ap_id(context).id
        end
    end
  end

  def conversation_id_to_context(id) do
    with %Object{data: %{"id" => context}} <- Repo.get(Object, id) do
      context
    else
      _e ->
        {:error, "No such conversation"}
    end
  end

  def get_external_profile(for_user, uri) do
    with %User{} = user <- User.get_or_fetch(uri) do
      {:ok, UserView.render("show.json", %{user: user, for: for_user})}
    else
      _e ->
        {:error, "Couldn't find user"}
    end
  end
end
