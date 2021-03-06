# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.TwitterAPI.UtilController do
  use Pleroma.Web, :controller

  require Logger

  alias Comeonin.Pbkdf2
  alias Pleroma.Emoji
  alias Pleroma.PasswordResetToken
  alias Pleroma.User
  alias Pleroma.Repo
  alias Pleroma.Web
  alias Pleroma.Web.CommonAPI
  alias Pleroma.Web.OStatus
  alias Pleroma.Web.WebFinger
  alias Pleroma.Web.ActivityPub.ActivityPub

  def show_password_reset(conn, %{"token" => token}) do
    with %{used: false} = token <- Repo.get_by(PasswordResetToken, %{token: token}),
         %User{} = user <- Repo.get(User, token.user_id) do
      render(conn, "password_reset.html", %{
        token: token,
        user: user
      })
    else
      _e -> render(conn, "invalid_token.html")
    end
  end

  def password_reset(conn, %{"data" => data}) do
    with {:ok, _} <- PasswordResetToken.reset_password(data["token"], data) do
      render(conn, "password_reset_success.html")
    else
      _e -> render(conn, "password_reset_failed.html")
    end
  end

  def help_test(conn, _params) do
    json(conn, "ok")
  end

  def remote_subscribe(conn, %{"nickname" => nick, "profile" => _}) do
    with %User{} = user <- User.get_cached_by_nickname(nick), avatar = User.avatar_url(user) do
      conn
      |> render("subscribe.html", %{nickname: nick, avatar: avatar, error: false})
    else
      _e ->
        render(conn, "subscribe.html", %{
          nickname: nick,
          avatar: nil,
          error: "Could not find user"
        })
    end
  end

  def remote_subscribe(conn, %{"user" => %{"nickname" => nick, "profile" => profile}}) do
    with {:ok, %{"subscribe_address" => template}} <- WebFinger.finger(profile),
         %User{ap_id: ap_id} <- User.get_cached_by_nickname(nick) do
      conn
      |> Phoenix.Controller.redirect(external: String.replace(template, "{uri}", ap_id))
    else
      _e ->
        render(conn, "subscribe.html", %{
          nickname: nick,
          avatar: nil,
          error: "Something went wrong."
        })
    end
  end

  def remote_follow(%{assigns: %{user: user}} = conn, %{"acct" => acct}) do
    {err, followee} = OStatus.find_or_make_user(acct)
    avatar = User.avatar_url(followee)
    name = followee.nickname
    id = followee.id

    if !!user do
      conn
      |> render("follow.html", %{error: err, acct: acct, avatar: avatar, name: name, id: id})
    else
      conn
      |> render("follow_login.html", %{
        error: false,
        acct: acct,
        avatar: avatar,
        name: name,
        id: id
      })
    end
  end

  def do_remote_follow(conn, %{
        "authorization" => %{"name" => username, "password" => password, "id" => id}
      }) do
    followee = Repo.get(User, id)
    avatar = User.avatar_url(followee)
    name = followee.nickname

    with %User{} = user <- User.get_cached_by_nickname(username),
         true <- Pbkdf2.checkpw(password, user.password_hash),
         %User{} = _followed <- Repo.get(User, id),
         {:ok, follower} <- User.follow(user, followee),
         {:ok, _activity} <- ActivityPub.follow(follower, followee) do
      conn
      |> render("followed.html", %{error: false})
    else
      # Was already following user
      {:error, "Could not follow user:" <> _rest} ->
        render(conn, "followed.html", %{error: false})

      _e ->
        conn
        |> render("follow_login.html", %{
          error: "Wrong username or password",
          id: id,
          name: name,
          avatar: avatar
        })
    end
  end

  def do_remote_follow(%{assigns: %{user: user}} = conn, %{"user" => %{"id" => id}}) do
    with %User{} = followee <- Repo.get(User, id),
         {:ok, follower} <- User.follow(user, followee),
         {:ok, _activity} <- ActivityPub.follow(follower, followee) do
      conn
      |> render("followed.html", %{error: false})
    else
      # Was already following user
      {:error, "Could not follow user:" <> _rest} ->
        conn
        |> render("followed.html", %{error: false})

      e ->
        Logger.debug("Remote follow failed with error #{inspect(e)}")

        conn
        |> render("followed.html", %{error: inspect(e)})
    end
  end

  def config(conn, _params) do
    instance = Pleroma.Config.get(:instance)
    instance_fe = Pleroma.Config.get(:fe)
    instance_chat = Pleroma.Config.get(:chat)

    case get_format(conn) do
      "xml" ->
        response = """
        <config>
          <site>
            <name>#{Keyword.get(instance, :name)}</name>
            <site>#{Web.base_url()}</site>
            <textlimit>#{Keyword.get(instance, :limit)}</textlimit>
            <closed>#{!Keyword.get(instance, :registrations_open)}</closed>
          </site>
        </config>
        """

        conn
        |> put_resp_content_type("application/xml")
        |> send_resp(200, response)

      _ ->
        vapid_public_key = Keyword.get(Pleroma.Web.Push.vapid_config(), :public_key)

        uploadlimit = %{
          uploadlimit: to_string(Keyword.get(instance, :upload_limit)),
          avatarlimit: to_string(Keyword.get(instance, :avatar_upload_limit)),
          backgroundlimit: to_string(Keyword.get(instance, :background_upload_limit)),
          bannerlimit: to_string(Keyword.get(instance, :banner_upload_limit))
        }

        data = %{
          name: Keyword.get(instance, :name),
          description: Keyword.get(instance, :description),
          server: Web.base_url(),
          textlimit: to_string(Keyword.get(instance, :limit)),
          uploadlimit: uploadlimit,
          closed: if(Keyword.get(instance, :registrations_open), do: "0", else: "1"),
          private: if(Keyword.get(instance, :public, true), do: "0", else: "1"),
          vapidPublicKey: vapid_public_key,
          accountActivationRequired:
            if(Keyword.get(instance, :account_activation_required, false), do: "1", else: "0"),
          invitesEnabled: if(Keyword.get(instance, :invites_enabled, false), do: "1", else: "0")
        }

        pleroma_fe =
          if instance_fe do
            %{
              theme: Keyword.get(instance_fe, :theme),
              background: Keyword.get(instance_fe, :background),
              logo: Keyword.get(instance_fe, :logo),
              logoMask: Keyword.get(instance_fe, :logo_mask),
              logoMargin: Keyword.get(instance_fe, :logo_margin),
              redirectRootNoLogin: Keyword.get(instance_fe, :redirect_root_no_login),
              redirectRootLogin: Keyword.get(instance_fe, :redirect_root_login),
              chatDisabled: !Keyword.get(instance_chat, :enabled),
              showInstanceSpecificPanel: Keyword.get(instance_fe, :show_instance_panel),
              scopeOptionsEnabled: Keyword.get(instance_fe, :scope_options_enabled),
              formattingOptionsEnabled: Keyword.get(instance_fe, :formatting_options_enabled),
              collapseMessageWithSubject:
                Keyword.get(instance_fe, :collapse_message_with_subject),
              hidePostStats: Keyword.get(instance_fe, :hide_post_stats),
              hideUserStats: Keyword.get(instance_fe, :hide_user_stats),
              scopeCopy: Keyword.get(instance_fe, :scope_copy),
              subjectLineBehavior: Keyword.get(instance_fe, :subject_line_behavior),
              alwaysShowSubjectInput: Keyword.get(instance_fe, :always_show_subject_input)
            }
          else
            Pleroma.Config.get([:frontend_configurations, :pleroma_fe])
          end

        managed_config = Keyword.get(instance, :managed_config)

        data =
          if managed_config do
            data |> Map.put("pleromafe", pleroma_fe)
          else
            data
          end

        json(conn, %{site: data})
    end
  end

  def frontend_configurations(conn, _params) do
    config =
      Pleroma.Config.get(:frontend_configurations, %{})
      |> Enum.into(%{})

    json(conn, config)
  end

  def version(conn, _params) do
    version = Pleroma.Application.named_version()

    case get_format(conn) do
      "xml" ->
        response = "<version>#{version}</version>"

        conn
        |> put_resp_content_type("application/xml")
        |> send_resp(200, response)

      _ ->
        json(conn, version)
    end
  end

  def emoji(conn, _params) do
    json(conn, Enum.into(Emoji.get_all(), %{}))
  end

  def follow_import(conn, %{"list" => %Plug.Upload{} = listfile}) do
    follow_import(conn, %{"list" => File.read!(listfile.path)})
  end

  def follow_import(%{assigns: %{user: follower}} = conn, %{"list" => list}) do
    with followed_identifiers <- String.split(list),
         {:ok, _} = Task.start(fn -> User.follow_import(follower, followed_identifiers) end) do
      json(conn, "job started")
    end
  end

  def blocks_import(conn, %{"list" => %Plug.Upload{} = listfile}) do
    blocks_import(conn, %{"list" => File.read!(listfile.path)})
  end

  def blocks_import(%{assigns: %{user: blocker}} = conn, %{"list" => list}) do
    with blocked_identifiers <- String.split(list),
         {:ok, _} = Task.start(fn -> User.blocks_import(blocker, blocked_identifiers) end) do
      json(conn, "job started")
    end
  end

  def change_password(%{assigns: %{user: user}} = conn, params) do
    case CommonAPI.Utils.confirm_current_password(user, params["password"]) do
      {:ok, user} ->
        with {:ok, _user} <-
               User.reset_password(user, %{
                 password: params["new_password"],
                 password_confirmation: params["new_password_confirmation"]
               }) do
          json(conn, %{status: "success"})
        else
          {:error, changeset} ->
            {_, {error, _}} = Enum.at(changeset.errors, 0)
            json(conn, %{error: "New password #{error}."})

          _ ->
            json(conn, %{error: "Unable to change password."})
        end

      {:error, msg} ->
        json(conn, %{error: msg})
    end
  end

  def delete_account(%{assigns: %{user: user}} = conn, params) do
    case CommonAPI.Utils.confirm_current_password(user, params["password"]) do
      {:ok, user} ->
        Task.start(fn -> User.delete(user) end)
        json(conn, %{status: "success"})

      {:error, msg} ->
        json(conn, %{error: msg})
    end
  end

  def captcha(conn, _params) do
    json(conn, Pleroma.Captcha.new())
  end
end
