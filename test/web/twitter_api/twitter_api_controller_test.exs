defmodule Pleroma.Web.TwitterAPI.ControllerTest do
  use Pleroma.Web.ConnCase
  alias Pleroma.Builders.{ActivityBuilder, UserBuilder}
  alias Pleroma.{Repo, Activity, User, Object}
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.TwitterAPI.{UserView, StatusView}

  import Pleroma.Factory

  # TODO: separate into individual controller tests

  describe "POST /api/account/verify_credentials" do
    setup [:valid_user]
    test "without valid credentials", %{conn: conn} do
      conn = post conn, "/api/account/verify_credentials.json"
      assert json_response(conn, 403) == %{"error" => "Invalid credentials."}
    end

    test "with credentials", %{conn: conn, user: user} do
      conn = conn
        |> with_credentials(user.nickname, "test")
        |> post("/api/account/verify_credentials.json")

      assert json_response(conn, 200) == UserView.render("show.json", %{user: user})
    end
  end

  describe "POST /statuses/update.json" do
    setup [:valid_user]
    test "without valid credentials", %{conn: conn} do
      conn = post conn, "/api/statuses/update.json"
      assert json_response(conn, 403) == %{"error" => "Invalid credentials."}
    end

    test "with credentials", %{conn: conn, user: user} do
      conn_with_creds = conn |> with_credentials(user.nickname, "test")
      request_path = "/api/statuses/update.json"

      error_response = %{"request" => request_path,
                         "error" => "Client must provide a 'status' parameter with a value."}
      conn = conn_with_creds |> post(request_path)
      assert json_response(conn, 400) == error_response

      conn = conn_with_creds |> post(request_path, %{ status: "" })
      assert json_response(conn, 400) == error_response

      conn = conn_with_creds |> post(request_path, %{ status: " " })
      assert json_response(conn, 400) == error_response

      conn =  conn_with_creds |> post(request_path, %{ status: "Nice meme." })
      assert json_response(conn, 200) == StatusView.render("show.json", %{activity: Repo.one(Activity)})
    end
  end

  describe "GET /statuses/public_timeline.json" do
    test "returns statuses", %{conn: conn} do
      {:ok, user} = UserBuilder.insert
      activities = ActivityBuilder.insert_list(30, %{}, %{user: user})
      ActivityBuilder.insert_list(10, %{}, %{user: user})
      since_id = List.last(activities).id

      conn = conn
        |> get("/api/statuses/public_timeline.json", %{since_id: since_id})

      response = json_response(conn, 200)

      assert length(response) == 10
    end
  end

  describe "GET /statuses/show/:id.json" do
    test "returns one status", %{conn: conn} do
      {:ok, user} = UserBuilder.insert
      {:ok, activity} = ActivityBuilder.insert(%{}, %{user: user})

      conn = conn
      |> get("/api/statuses/show/#{activity.id}.json")

      response = json_response(conn, 200)

      assert response == StatusView.render("show.json", %{activity: activity})
    end
  end

  describe "GET /statusnet/conversation/:id.json" do
    test "returns the statuses in the conversation", %{conn: conn} do
      {:ok, _user} = UserBuilder.insert
      {:ok, _activity} = ActivityBuilder.insert(%{"context" => "2hu"})
      {:ok, _activity_two} = ActivityBuilder.insert(%{"context" => "2hu"})
      {:ok, _activity_three} = ActivityBuilder.insert(%{"context" => "3hu"})

      {:ok, object} = Object.context_mapping("2hu") |> Repo.insert
      conn = conn
      |> get("/api/statusnet/conversation/#{object.id}.json")

      response = json_response(conn, 200)

      assert length(response) == 2
    end
  end

  describe "GET /statuses/friends_timeline.json" do
    setup [:valid_user]
    test "without valid credentials", %{conn: conn} do
      conn = get conn, "/api/statuses/friends_timeline.json"
      assert json_response(conn, 403) == %{"error" => "Invalid credentials."}
    end

    test "with credentials", %{conn: conn, user: current_user} do
      user = insert(:user)
      activities = ActivityBuilder.insert_list(30, %{"to" => [User.ap_followers(user)]}, %{user: user})
      returned_activities = ActivityBuilder.insert_list(10, %{"to" => [User.ap_followers(user)]}, %{user: user})
      other_user = insert(:user)
      ActivityBuilder.insert_list(10, %{}, %{user: other_user})
      since_id = List.last(activities).id

      current_user = Ecto.Changeset.change(current_user, following: [User.ap_followers(user)]) |> Repo.update!

      conn = conn
        |> with_credentials(current_user.nickname, "test")
        |> get("/api/statuses/friends_timeline.json", %{since_id: since_id})

      response = json_response(conn, 200)

      assert length(response) == 10
      assert response == StatusView.render("timeline.json", %{activities: returned_activities, for: current_user})
    end
  end

  describe "GET /statuses/mentions.json" do
    setup [:valid_user]
    test "without valid credentials", %{conn: conn} do
      conn = get conn, "/api/statuses/mentions.json"
      assert json_response(conn, 403) == %{"error" => "Invalid credentials."}
    end

    test "with credentials", %{conn: conn, user: current_user} do
      {:ok, activity} = ActivityBuilder.insert(%{"to" => [current_user.ap_id]}, %{user: current_user})

      conn = conn
        |> with_credentials(current_user.nickname, "test")
        |> get("/api/statuses/mentions.json")

      response = json_response(conn, 200)

      assert length(response) == 1
      assert Enum.at(response, 0) == StatusView.render("show.json", %{activity: activity})
    end
  end

  describe "GET /statuses/user_timeline.json" do
    setup [:valid_user]
    test "without any params", %{conn: conn} do
      conn = get(conn, "/api/statuses/user_timeline.json")
      assert json_response(conn, 400) == %{"error" => "You need to specify screen_name or user_id", "request" => "/api/statuses/user_timeline.json"}
    end

    test "with user_id", %{conn: conn} do
      user = insert(:user)
      {:ok, activity} = ActivityBuilder.insert(%{"id" => 1}, %{user: user})

      conn = get(conn, "/api/statuses/user_timeline.json", %{"user_id" => user.id})
      response = json_response(conn, 200)
      assert length(response) == 1
      assert Enum.at(response, 0) == StatusView.render("show.json", %{activity: activity})
    end

    test "with screen_name", %{conn: conn} do
      user = insert(:user)
      {:ok, activity} = ActivityBuilder.insert(%{"id" => 1}, %{user: user})

      conn = get(conn, "/api/statuses/user_timeline.json", %{"screen_name" => user.nickname})
      response = json_response(conn, 200)
      assert length(response) == 1
      assert Enum.at(response, 0) == StatusView.render("show.json", %{activity: activity})
    end

    test "with credentials", %{conn: conn, user: current_user} do
      {:ok, activity} = ActivityBuilder.insert(%{"id" => 1}, %{user: current_user})
      conn = conn
      |> with_credentials(current_user.nickname, "test")
      |> get("/api/statuses/user_timeline.json")

      response = json_response(conn, 200)

      assert length(response) == 1
      assert Enum.at(response, 0) == StatusView.render("show.json", %{activity: activity})
    end

    test "with credentials with user_id", %{conn: conn, user: current_user} do
      user = insert(:user)
      {:ok, activity} = ActivityBuilder.insert(%{"id" => 1}, %{user: user})
      conn = conn
      |> with_credentials(current_user.nickname, "test")
      |> get("/api/statuses/user_timeline.json", %{"user_id" => user.id})

      response = json_response(conn, 200)

      assert length(response) == 1
      assert Enum.at(response, 0) == StatusView.render("show.json", %{activity: activity})
    end

    test "with credentials screen_name", %{conn: conn, user: current_user} do
      user = insert(:user)
      {:ok, activity} = ActivityBuilder.insert(%{"id" => 1}, %{user: user})
      conn = conn
      |> with_credentials(current_user.nickname, "test")
      |> get("/api/statuses/user_timeline.json", %{"screen_name" => user.nickname})

      response = json_response(conn, 200)

      assert length(response) == 1
      assert Enum.at(response, 0) == StatusView.render("show.json", %{activity: activity})
    end
  end

  describe "POST /friendships/create.json" do
    setup [:valid_user]
    test "without valid credentials", %{conn: conn} do
      conn = post conn, "/api/friendships/create.json"
      assert json_response(conn, 403) == %{"error" => "Invalid credentials."}
    end

    test "with credentials", %{conn: conn, user: current_user} do
      followed = insert(:user)

      conn = conn
      |> with_credentials(current_user.nickname, "test")
      |> post("/api/friendships/create.json", %{user_id: followed.id})

      current_user = Repo.get(User, current_user.id)
      assert current_user.following == [User.ap_followers(followed)]
      assert json_response(conn, 200) == UserView.render("show.json", %{user: followed, for: current_user})
    end
  end

  describe "POST /friendships/destroy.json" do
    setup [:valid_user]
    test "without valid credentials", %{conn: conn} do
      conn = post conn, "/api/friendships/destroy.json"
      assert json_response(conn, 403) == %{"error" => "Invalid credentials."}
    end

    test "with credentials", %{conn: conn, user: current_user} do
      followed = insert(:user)

      {:ok, current_user} = User.follow(current_user, followed)
      assert current_user.following == [User.ap_followers(followed)]
      ActivityPub.follow(current_user, followed)

      conn = conn
      |> with_credentials(current_user.nickname, "test")
      |> post("/api/friendships/destroy.json", %{user_id: followed.id})

      current_user = Repo.get(User, current_user.id)
      assert current_user.following == []
      assert json_response(conn, 200) == UserView.render("show.json", %{user: followed, for: current_user})
    end
  end

  describe "GET /help/test.json" do
    test "returns \"ok\"", %{conn: conn} do
      conn = get conn, "/api/help/test.json"
      assert json_response(conn, 200) == "ok"
    end
  end

  describe "POST /api/qvitter/update_avatar.json" do
    setup [:valid_user]
    test "without valid credentials", %{conn: conn} do
      conn = post conn, "/api/qvitter/update_avatar.json"
      assert json_response(conn, 403) == %{"error" => "Invalid credentials."}
    end

    test "with credentials", %{conn: conn, user: current_user} do
      conn = conn
      |> with_credentials(current_user.nickname, "test")
      |> post("/api/qvitter/update_avatar.json", %{img: Pleroma.Web.ActivityPub.ActivityPubTest.data_uri})

      current_user = Repo.get(User, current_user.id)
      assert is_map(current_user.avatar)
      assert json_response(conn, 200) == UserView.render("show.json", %{user: current_user, for: current_user})
    end
  end

  describe "POST /api/favorites/create/:id" do
    setup [:valid_user]
    test "without valid credentials", %{conn: conn} do
      note_activity = insert(:note_activity)
      conn = post conn, "/api/favorites/create/#{note_activity.id}.json"
      assert json_response(conn, 403) == %{"error" => "Invalid credentials."}
    end

    test "with credentials", %{conn: conn, user: current_user} do
      note_activity = insert(:note_activity)

      conn = conn
      |> with_credentials(current_user.nickname, "test")
      |> post("/api/favorites/create/#{note_activity.id}.json")

      assert json_response(conn, 200)
    end
  end

  describe "POST /api/favorites/destroy/:id" do
    setup [:valid_user]
    test "without valid credentials", %{conn: conn} do
      note_activity = insert(:note_activity)
      conn = post conn, "/api/favorites/destroy/#{note_activity.id}.json"
      assert json_response(conn, 403) == %{"error" => "Invalid credentials."}
    end

    test "with credentials", %{conn: conn, user: current_user} do
      note_activity = insert(:note_activity)
      object = Object.get_by_ap_id(note_activity.data["object"]["id"])
      ActivityPub.like(current_user, object)

      conn = conn
      |> with_credentials(current_user.nickname, "test")
      |> post("/api/favorites/destroy/#{note_activity.id}.json")

      assert json_response(conn, 200)
    end
  end

  describe "POST /api/statuses/retweet/:id" do
    setup [:valid_user]
    test "without valid credentials", %{conn: conn} do
      note_activity = insert(:note_activity)
      conn = post conn, "/api/statuses/retweet/#{note_activity.id}.json"
      assert json_response(conn, 403) == %{"error" => "Invalid credentials."}
    end

    test "with credentials", %{conn: conn, user: current_user} do
      note_activity = insert(:note_activity)

      request_path = "/api/statuses/retweet/#{note_activity.id}.json"

      user = Repo.get_by(User, ap_id: note_activity.data["actor"])
      response = conn
      |> with_credentials(user.nickname, "test")
      |> post(request_path)
      assert json_response(response, 400) == %{"error" => "You cannot repeat your own status.",
                                               "request" => request_path}

      response = conn
      |> with_credentials(current_user.nickname, "test")
      |> post(request_path)
      activity = Repo.get(Activity, note_activity.id)
      assert json_response(response, 200) == StatusView.render("show.json", %{activity: activity, for: current_user})
    end
  end

  describe "POST /api/account/register" do
    test "it creates a new user", %{conn: conn} do
      data = %{
        "nickname" => "lain",
        "email" => "lain@wired.jp",
        "fullname" => "lain iwakura",
        "bio" => "close the world.",
        "password" => "bear",
        "confirm" => "bear"
      }

      conn = conn
      |> post("/api/account/register", data)

      user = json_response(conn, 200)

      fetched_user = Repo.get_by(User, nickname: "lain")
      assert user == UserView.render("show.json", %{user: fetched_user})
    end

    test "it returns errors on a problem", %{conn: conn} do
      data = %{
        "email" => "lain@wired.jp",
        "fullname" => "lain iwakura",
        "bio" => "close the world.",
        "password" => "bear",
        "confirm" => "bear"
      }

      conn = conn
      |> post("/api/account/register", data)

      errors = json_response(conn, 400)

      assert errors["error"]
    end
  end

  defp valid_user(_context) do
    user = insert(:user)
    [user: user]
  end

  defp with_credentials(conn, username, password) do
    header_content = "Basic " <> Base.encode64("#{username}:#{password}")
    put_req_header(conn, "authorization", header_content)
  end
end
