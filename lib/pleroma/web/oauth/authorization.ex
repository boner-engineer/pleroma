# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.OAuth.Authorization do
  use Ecto.Schema

  alias Pleroma.User
  alias Pleroma.Repo
  alias Pleroma.Web.OAuth.Authorization
  alias Pleroma.Web.OAuth.App

  import Ecto.Changeset
  import Ecto.Query

  schema "oauth_authorizations" do
    field(:token, :string)
    field(:scopes, {:array, :string}, default: [])
    field(:valid_until, :naive_datetime)
    field(:used, :boolean, default: false)
    belongs_to(:user, Pleroma.User, type: Pleroma.FlakeId)
    belongs_to(:app, App)

    timestamps()
  end

  def create_authorization(%App{} = app, %User{} = user, scopes \\ nil) do
    scopes = scopes || app.scopes
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    authorization = %Authorization{
      token: token,
      used: false,
      user_id: user.id,
      app_id: app.id,
      scopes: scopes,
      valid_until: NaiveDateTime.add(NaiveDateTime.utc_now(), 60 * 10)
    }

    Repo.insert(authorization)
  end

  def use_changeset(%Authorization{} = auth, params) do
    auth
    |> cast(params, [:used])
    |> validate_required([:used])
  end

  def use_token(%Authorization{used: false, valid_until: valid_until} = auth) do
    if NaiveDateTime.diff(NaiveDateTime.utc_now(), valid_until) < 0 do
      Repo.update(use_changeset(auth, %{used: true}))
    else
      {:error, "token expired"}
    end
  end

  def use_token(%Authorization{used: true}), do: {:error, "already used"}

  def delete_user_authorizations(%User{id: user_id}) do
    from(
      a in Pleroma.Web.OAuth.Authorization,
      where: a.user_id == ^user_id
    )
    |> Repo.delete_all()
  end
end
