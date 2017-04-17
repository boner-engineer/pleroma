defmodule Pleroma.Web.Router do
  use Pleroma.Web, :router

  alias Pleroma.{Repo, User}

  def user_fetcher(username) do
    {:ok, Repo.get_by(User, %{nickname: username})}
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug Pleroma.Plugs.AuthenticationPlug, %{fetcher: &Pleroma.Web.Router.user_fetcher/1, optional: true}
  end

  pipeline :authenticated_api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug Pleroma.Plugs.AuthenticationPlug, %{fetcher: &Pleroma.Web.Router.user_fetcher/1}
  end

  scope "/api", Pleroma.Web do
    pipe_through :api

    get "/help/test", TwitterAPI.Controller, :help_test
    get "/statuses/public_timeline", TwitterAPI.Controller, :public_timeline
    get "/statuses/public_and_external_timeline", TwitterAPI.Controller, :public_timeline
    get "/statuses/show/:id", TwitterAPI.Controller, :fetch_status
    get "/statusnet/conversation/:id", TwitterAPI.Controller, :fetch_conversation
    get "/statusnet/config", TwitterAPI.Controller, :config
    post "/account/register", TwitterAPI.Controller, :register
  end

  scope "/api", Pleroma.Web do
    pipe_through :authenticated_api

    get "/account/verify_credentials", TwitterAPI.Controller, :verify_credentials
    post "/account/verify_credentials", TwitterAPI.Controller, :verify_credentials
    post "/statuses/update", TwitterAPI.Controller, :status_update
    get "/statuses/home_timeline", TwitterAPI.Controller, :friends_timeline
    get "/statuses/friends_timeline", TwitterAPI.Controller, :friends_timeline
    post "/friendships/create", TwitterAPI.Controller, :follow
    post "/friendships/destroy", TwitterAPI.Controller, :unfollow
    post "/statusnet/media/upload", TwitterAPI.Controller, :upload
    post "/media/upload", TwitterAPI.Controller, :upload_json
    post "/favorites/create/:id", TwitterAPI.Controller, :favorite
    post "/favorites/create", TwitterAPI.Controller, :favorite
    post "/favorites/destroy/:id", TwitterAPI.Controller, :unfavorite
    post "/statuses/retweet/:id", TwitterAPI.Controller, :retweet
    post "/qvitter/update_avatar", TwitterAPI.Controller, :update_avatar
  end
end
