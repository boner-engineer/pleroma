defmodule Pleroma.Web.MastodonAPI.MastodonAPIController do
  use Pleroma.Web, :controller
  alias Pleroma.{Repo, Activity, User, Notification}
  alias Pleroma.Web.OAuth.App
  alias Pleroma.Web
  alias Pleroma.Web.MastodonAPI.{StatusView, AccountView, NotificationView}
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.TwitterAPI.TwitterAPI
  alias Pleroma.Web.CommonAPI
  alias Pleroma.Web.Streamer
  import Ecto.Query
  import Logger

  def create_app(conn, params) do
    with cs <- App.register_changeset(%App{}, params) |> IO.inspect,
         {:ok, app} <- Repo.insert(cs) |> IO.inspect do
      res = %{
        id: app.id,
        client_id: app.client_id,
        client_secret: app.client_secret
      }

      json(conn, res)
    end
  end

  def verify_credentials(%{assigns: %{user: user}} = conn, params) do
    account = AccountView.render("account.json", %{user: user})
    json(conn, account)
  end

  def user(conn, %{"id" => id}) do
    with %User{} = user <- Repo.get(User, id) do
      account = AccountView.render("account.json", %{user: user})
      json(conn, account)
    else
      _e -> conn
      |> put_status(404)
      |> json(%{error: "Can't find user"})
    end
  end

  @instance Application.get_env(:pleroma, :instance)

  def masto_instance(conn, _params) do
    response = %{
      uri: Web.base_url,
      title: Keyword.get(@instance, :name),
      description: "A Pleroma instance, an alternative fediverse server",
      version: Keyword.get(@instance, :version),
      email: Keyword.get(@instance, :email),
      urls: %{
        streaming_api: String.replace(Web.base_url, ["http","https"], "wss")
      },
      stats: %{
        user_count: 1,
        status_count: 2,
        domain_count: 3
      }
    }

    json(conn, response)
  end

  def custom_emojis(conn, _params) do
    mastodon_emoji = Pleroma.Formatter.get_custom_emoji()
    |> Enum.map(fn {shortcode, relative_url} ->
      url = to_string URI.merge(Web.base_url(), relative_url)
      %{
        "shortcode" => shortcode,
        "static_url" => url,
        "url" => url
      }
    end)
    json conn, mastodon_emoji
  end

  defp add_link_headers(conn, method, activities) do
    last = List.last(activities)
    first = List.first(activities)
    if last do
      min = last.id
      max = first.id
      next_url = mastodon_api_url(Pleroma.Web.Endpoint, method, max_id: min)
      prev_url = mastodon_api_url(Pleroma.Web.Endpoint, method, since_id: max)
      conn
      |> put_resp_header("link", "<#{next_url}>; rel=\"next\", <#{prev_url}>; rel=\"prev\"")
    else
      conn
    end
  end

  def home_timeline(%{assigns: %{user: user}} = conn, params) do
    params = params
    |> Map.put("type", ["Create", "Announce"])
    |> Map.put("blocking_user", user)

    activities = ActivityPub.fetch_activities([user.ap_id | user.following], params)
    |> Enum.reverse

    conn
    |> add_link_headers(:home_timeline, activities)
    |> render(StatusView, "index.json", %{activities: activities, for: user, as: :activity})
  end

  def public_timeline(%{assigns: %{user: user}} = conn, params) do
    params = params
    |> Map.put("type", ["Create", "Announce"])
    |> Map.put("local_only", !!params["local"])
    |> Map.put("blocking_user", user)

    activities = ActivityPub.fetch_public_activities(params)
    |> Enum.reverse

    conn
    |> add_link_headers(:public_timeline, activities)
    |> render(StatusView, "index.json", %{activities: activities, for: user, as: :activity})
  end

  # TODO: Link headers
  def user_statuses(%{assigns: %{user: user}} = conn, params) do
    with %User{ap_id: ap_id} <- Repo.get(User, params["id"]) do
      params = params
      |> Map.put("type", ["Create", "Announce"])
      |> Map.put("actor_id", ap_id)
      |> Map.put("whole_db", true)

      activities = ActivityPub.fetch_activities([], params)
      |> Enum.reverse

      render conn, StatusView, "index.json", %{activities: activities, for: user, as: :activity}
    end
  end

  def get_status(%{assigns: %{user: user}} = conn, %{"id" => id}) do
    with %Activity{} = activity <- Repo.get(Activity, id) do
      render conn, StatusView, "status.json", %{activity: activity, for: user}
    end
  end

  def get_context(%{assigns: %{user: user}} = conn, %{"id" => id}) do
    with %Activity{} = activity <- Repo.get(Activity, id),
         activities <- ActivityPub.fetch_activities_for_context(activity.data["object"]["context"], %{"blocking_user" => user}),
         activities <- activities |> Enum.filter(fn (%{id: aid}) -> to_string(aid) != to_string(id) end),
         grouped_activities <- Enum.group_by(activities, fn (%{id: id}) -> id < activity.id end) do
      result = %{
        ancestors: StatusView.render("index.json", for: user, activities: grouped_activities[true] || [], as: :activity) |> Enum.reverse,
        descendants: StatusView.render("index.json", for: user, activities: grouped_activities[false] || [], as: :activity) |> Enum.reverse,
      }

      json(conn, result)
    end
  end

  def post_status(%{assigns: %{user: user}} = conn, %{"status" => status} = params) do
    params = params
    |> Map.put("in_reply_to_status_id", params["in_reply_to_id"])

    {:ok, activity} = CommonAPI.post(user, params)
    render conn, StatusView, "status.json", %{activity: activity, for: user, as: :activity}
  end

  def delete_status(%{assigns: %{user: user}} = conn, %{"id" => id}) do
    with {:ok, %Activity{}} <- CommonAPI.delete(id, user) do
      json(conn, %{})
    else
      _e ->
        conn
        |> put_status(403)
        |> json(%{error: "Can't delete this post"})
    end
  end

  def reblog_status(%{assigns: %{user: user}} = conn, %{"id" => ap_id_or_id}) do
    with {:ok, _announce, %{data: %{"id" => id}}} = CommonAPI.repeat(ap_id_or_id, user),
         %Activity{} = activity <- Activity.get_create_activity_by_object_ap_id(id) do
      render conn, StatusView, "status.json", %{activity: activity, for: user, as: :activity}
    end
  end

  def fav_status(%{assigns: %{user: user}} = conn, %{"id" => ap_id_or_id}) do
    with {:ok, _fav, %{data: %{"id" => id}}} = CommonAPI.favorite(ap_id_or_id, user),
         %Activity{} = activity <- Activity.get_create_activity_by_object_ap_id(id) do
      render conn, StatusView, "status.json", %{activity: activity, for: user, as: :activity}
    end
  end

  def unfav_status(%{assigns: %{user: user}} = conn, %{"id" => ap_id_or_id}) do
    with {:ok, %{data: %{"id" => id}}} = CommonAPI.unfavorite(ap_id_or_id, user),
         %Activity{} = activity <- Activity.get_create_activity_by_object_ap_id(id) do
      render conn, StatusView, "status.json", %{activity: activity, for: user, as: :activity}
    end
  end

  def notifications(%{assigns: %{user: user}} = conn, params) do
    notifications = Notification.for_user(user, params)
    result = Enum.map(notifications, fn (notification) ->
      NotificationView.render("notification.json", %{notification: notification})
    end)
    |> Enum.filter(&(&1))

    conn
    |> add_link_headers(:notifications, notifications)
    |> json(result)
  end

  def relationships(%{assigns: %{user: user}} = conn, %{"id" => id}) do
    id = List.wrap(id)
    q = from u in User,
      where: u.id in ^id
    targets = Repo.all(q)
    render conn, AccountView, "relationships.json", %{user: user, targets: targets}
  end

  def upload(%{assigns: %{user: user}} = conn, %{"file" => file}) do
    with {:ok, object} <- ActivityPub.upload(file) do
      data = object.data
      |> Map.put("id", object.id)

      render conn, StatusView, "attachment.json", %{attachment: data}
    end
  end

  def favourited_by(conn, %{"id" => id}) do
    with %Activity{data: %{"object" => %{"likes" => likes} = data}} <- Repo.get(Activity, id) do
      q = from u in User,
        where: u.ap_id in ^likes
      users = Repo.all(q)
      render conn, AccountView, "accounts.json", %{users: users, as: :user}
    else
      _ -> json(conn, [])
    end
  end

  def reblogged_by(conn, %{"id" => id}) do
    with %Activity{data: %{"object" => %{"announcements" => announces}}} <- Repo.get(Activity, id) do
      q = from u in User,
        where: u.ap_id in ^announces
      users = Repo.all(q)
      render conn, AccountView, "accounts.json", %{users: users, as: :user}
    else
      _ -> json(conn, [])
    end
  end

  # TODO: Link headers
  def hashtag_timeline(%{assigns: %{user: user}} = conn, params) do
    params = params
    |> Map.put("type", "Create")
    |> Map.put("local_only", !!params["local"])
    |> Map.put("blocking_user", user)

    activities = ActivityPub.fetch_public_activities(params)
    |> Enum.reverse

    conn
    |> render(StatusView, "index.json", %{activities: activities, for: user, as: :activity})
  end

  # TODO: Pagination
  def followers(conn, %{"id" => id}) do
    with %User{} = user <- Repo.get(User, id),
         {:ok, followers} <- User.get_followers(user) do
      render conn, AccountView, "accounts.json", %{users: followers, as: :user}
    end
  end

  def following(conn, %{"id" => id}) do
    with %User{} = user <- Repo.get(User, id),
         {:ok, followers} <- User.get_friends(user) do
      render conn, AccountView, "accounts.json", %{users: followers, as: :user}
    end
  end

  def follow(%{assigns: %{user: follower}} = conn, %{"id" => id}) do
    with %User{} = followed <- Repo.get(User, id),
         {:ok, follower} <- User.follow(follower, followed),
         {:ok, activity} <- ActivityPub.follow(follower, followed) do
      render conn, AccountView, "relationship.json", %{user: follower, target: followed}
    else
      {:error, message} = err ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, Poison.encode!(%{"error" => message}))
    end
  end

  def follow(%{assigns: %{user: follower}} = conn, %{"uri" => uri}) do
    with %User{} = followed <- Repo.get_by(User, nickname: uri),
         {:ok, follower} <- User.follow(follower, followed),
         {:ok, activity} <- ActivityPub.follow(follower, followed) do
      render conn, AccountView, "account.json", %{user: followed}
    else
      {:error, message} = err ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, Poison.encode!(%{"error" => message}))
    end
  end

  # TODO: Clean up and unify
  def unfollow(%{assigns: %{user: follower}} = conn, %{"id" => id}) do
    with %User{} = followed <- Repo.get(User, id),
         { :ok, follower, follow_activity } <- User.unfollow(follower, followed),
         { :ok, _activity } <- ActivityPub.insert(%{
           "type" => "Undo",
           "actor" => follower.ap_id,
           "object" => follow_activity.data["id"] # get latest Follow for these users
         }) do
      render conn, AccountView, "relationship.json", %{user: follower, target: followed}
    end
  end

  def block(%{assigns: %{user: blocker}} = conn, %{"id" => id}) do
    with %User{} = blocked <- Repo.get(User, id),
         {:ok, blocker} <- User.block(blocker, blocked) do
      render conn, AccountView, "relationship.json", %{user: blocker, target: blocked}
    else
      {:error, message} = err ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, Poison.encode!(%{"error" => message}))
    end
  end

  def unblock(%{assigns: %{user: blocker}} = conn, %{"id" => id}) do
    with %User{} = blocked <- Repo.get(User, id),
         {:ok, blocker} <- User.unblock(blocker, blocked) do
      render conn, AccountView, "relationship.json", %{user: blocker, target: blocked}
    else
      {:error, message} = err ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, Poison.encode!(%{"error" => message}))
    end
  end

  # TODO: Use proper query
  def blocks(%{assigns: %{user: user}} = conn, _) do
    with blocked_users <- user.info["blocks"] || [],
         accounts <- Enum.map(blocked_users, fn (ap_id) -> User.get_cached_by_ap_id(ap_id) end) do
      res = AccountView.render("accounts.json", users: accounts, for: user, as: :user)
      json(conn, res)
    end
  end

  def search(%{assigns: %{user: user}} = conn, %{"q" => query} = params) do
    accounts = User.search(query, params["resolve"] == "true")

    q = from a in Activity,
      where: fragment("?->>'type' = 'Create'", a.data),
      where: fragment("to_tsvector('english', ?->'object'->>'content') @@ plainto_tsquery('english', ?)", a.data, ^query),
      limit: 20
    statuses = Repo.all(q)

    res = %{
      "accounts" => AccountView.render("accounts.json", users: accounts, for: user, as: :user),
      "statuses" => StatusView.render("index.json", activities: statuses, for: user, as: :activity),
      "hashtags" => []
    }

    json(conn, res)
  end

  def account_search(%{assigns: %{user: user}} = conn, %{"q" => query} = params) do
    accounts = User.search(query, params["resolve"] == "true")

    res = AccountView.render("accounts.json", users: accounts, for: user, as: :user)

    json(conn, res)
  end

  def favourites(%{assigns: %{user: user}} = conn, params) do
    params = conn
    |> Map.put("type", "Create")
    |> Map.put("favorited_by", user.ap_id)
    |> Map.put("blocking_user", user)

    activities = ActivityPub.fetch_activities([], params)
    |> Enum.reverse

    conn
    |> render(StatusView, "index.json", %{activities: activities, for: user, as: :activity})
  end

  def stream_user(%{assigns: %{user: user}} = conn, _params) do
    Streamer.add_conn(user, conn)
    receive do
    end
  end

  def relationship_noop(%{assigns: %{user: user}} = conn, %{"id" => id}) do
    Logger.debug("Unimplemented, returning unmodified relationship")
    with %User{} = target <- Repo.get(User, id) do
      render conn, AccountView, "relationship.json", %{user: user, target: target}
    end
  end

  def empty_array(conn, _) do
    Logger.debug("Unimplemented, returning an empty array")
    json(conn, [])
  end
end
