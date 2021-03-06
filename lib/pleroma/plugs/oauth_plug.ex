# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Plugs.OAuthPlug do
  import Plug.Conn
  import Ecto.Query

  alias Pleroma.User
  alias Pleroma.Repo
  alias Pleroma.Web.OAuth.Token

  @realm_reg Regex.compile!("Bearer\:?\s+(.*)$", "i")

  def init(options), do: options

  def call(%{assigns: %{user: %User{}}} = conn, _), do: conn

  def call(conn, _) do
    with {:ok, token_str} <- fetch_token_str(conn),
         {:ok, user, token_record} <- fetch_user_and_token(token_str) do
      conn
      |> assign(:token, token_record)
      |> assign(:user, user)
    else
      _ -> conn
    end
  end

  # Gets user by token
  #
  @spec fetch_user_and_token(String.t()) :: {:ok, User.t(), Token.t()} | nil
  defp fetch_user_and_token(token) do
    query =
      from(t in Token,
        where: t.token == ^token,
        join: user in assoc(t, :user),
        preload: [user: user]
      )

    with %Token{user: %{info: %{deactivated: false} = _} = user} = token_record <- Repo.one(query) do
      {:ok, user, token_record}
    end
  end

  # Gets token from session by :oauth_token key
  #
  @spec fetch_token_from_session(Plug.Conn.t()) :: :no_token_found | {:ok, String.t()}
  defp fetch_token_from_session(conn) do
    case get_session(conn, :oauth_token) do
      nil -> :no_token_found
      token -> {:ok, token}
    end
  end

  # Gets token from headers
  #
  @spec fetch_token_str(Plug.Conn.t()) :: :no_token_found | {:ok, String.t()}
  defp fetch_token_str(%Plug.Conn{} = conn) do
    headers = get_req_header(conn, "authorization")

    with :no_token_found <- fetch_token_str(headers),
         do: fetch_token_from_session(conn)
  end

  @spec fetch_token_str(Keyword.t()) :: :no_token_found | {:ok, String.t()}
  defp fetch_token_str([]), do: :no_token_found

  defp fetch_token_str([token | tail]) do
    trimmed_token = String.trim(token)

    case Regex.run(@realm_reg, trimmed_token) do
      [_, match] -> {:ok, String.trim(match)}
      _ -> fetch_token_str(tail)
    end
  end
end
