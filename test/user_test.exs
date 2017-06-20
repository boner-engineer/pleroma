defmodule Pleroma.UserTest do
  alias Pleroma.Builders.UserBuilder
  alias Pleroma.{User, Repo}
  alias Pleroma.Web.OStatus
  alias Pleroma.Web.Websub.WebsubClientSubscription
  use Pleroma.DataCase

  import Pleroma.Factory
  import Ecto.Query

  test "ap_id returns the activity pub id for the user" do
    user = UserBuilder.build

    expected_ap_id = "#{Pleroma.Web.base_url}/users/#{user.nickname}"

    assert expected_ap_id == User.ap_id(user)
  end

  test "ap_followers returns the followers collection for the user" do
    user = UserBuilder.build

    expected_followers_collection = "#{User.ap_id(user)}/followers"

    assert expected_followers_collection == User.ap_followers(user)
  end

  test "follow takes a user and another user" do
    user = insert(:user)
    followed = insert(:user)

    {:ok, user} = User.follow(user, followed)

    user = Repo.get(User, user.id)

    assert user.following == [User.ap_followers(followed)]
  end

  test "following a remote user will ensure a websub subscription is present" do
    user = insert(:user)
    {:ok, followed} = OStatus.make_user("shp@social.heldscal.la")

    assert followed.local == false

    {:ok, user} = User.follow(user, followed)
    assert user.following == [User.ap_followers(followed)]

    query = from w in WebsubClientSubscription,
    where: w.topic == ^followed.info["topic"]
    websub = Repo.one(query)

    assert websub
  end

  test "unfollow takes a user and another user" do
    followed = insert(:user)
    user = insert(:user, %{following: [User.ap_followers(followed)]})

    {:ok, user, _activity } = User.unfollow(user, followed)

    user = Repo.get(User, user.id)

    assert user.following == []
  end

  test "test if a user is following another user" do
    followed = insert(:user)
    user = insert(:user, %{following: [User.ap_followers(followed)]})

    assert User.following?(user, followed)
    refute User.following?(followed, user)
  end

  describe "user registration" do
    @full_user_data %{
      bio: "A guy",
      name: "my name",
      nickname: "nick",
      password: "test",
      password_confirmation: "test",
      email: "email@example.com"
    }

    test "it requires a bio, email, name, nickname and password" do
      @full_user_data
      |> Map.keys
      |> Enum.each(fn (key) ->
        params = Map.delete(@full_user_data, key)
        changeset = User.register_changeset(%User{}, params)
        assert changeset.valid? == false
      end)
    end

    test "it sets the password_hash, ap_id and following fields" do
      changeset = User.register_changeset(%User{}, @full_user_data)

      assert changeset.valid?

      assert is_binary(changeset.changes[:password_hash])
      assert changeset.changes[:ap_id] == User.ap_id(%User{nickname: @full_user_data.nickname})
      assert changeset.changes[:following] == [User.ap_followers(%User{nickname: @full_user_data.nickname})]
    end
  end

  describe "fetching a user from nickname or trying to build one" do
    test "gets an existing user" do
      user = insert(:user)
      fetched_user = User.get_or_fetch_by_nickname(user.nickname)

      assert user == fetched_user
    end

    test "gets an existing user, case insensitive" do
      user = insert(:user, nickname: "nick")
      fetched_user = User.get_or_fetch_by_nickname("NICK")

      assert user == fetched_user
    end

    test "fetches an external user via ostatus if no user exists" do
      fetched_user = User.get_or_fetch_by_nickname("shp@social.heldscal.la")
      assert fetched_user.nickname == "shp@social.heldscal.la"
    end

    test "returns nil if no user could be fetched" do
      fetched_user = User.get_or_fetch_by_nickname("nonexistant@social.heldscal.la")
      assert fetched_user == nil
    end

    test "returns nil for nonexistant local user" do
      fetched_user = User.get_or_fetch_by_nickname("nonexistant")
      assert fetched_user == nil
    end
  end

  test "returns an ap_id for a user" do
    user = insert(:user)
    assert User.ap_id(user) == Pleroma.Web.Router.Helpers.o_status_url(Pleroma.Web.Endpoint, :feed_redirect, user.nickname)
  end

  test "returns an ap_followers link for a user" do
    user = insert(:user)
    assert User.ap_followers(user) == Pleroma.Web.Router.Helpers.o_status_url(Pleroma.Web.Endpoint, :feed_redirect, user.nickname) <> "/followers"
  end

  describe "remote user creation changeset" do
    @valid_remote %{
      bio: "hello",
      name: "Someone",
      nickname: "a@b.de",
      ap_id: "http...",
      info: %{some: "info"},
      avatar: %{some: "avatar"}
    }

    test "it confirms validity" do
      cs = User.remote_user_creation(@valid_remote)
      assert cs.valid?
    end

    test "it enforces the fqn format for nicknames" do
      cs = User.remote_user_creation(%{@valid_remote | nickname: "bla"})
      assert cs.changes.local == false
      assert cs.changes.avatar
      refute cs.valid?
    end

    test "it has required fields" do
      [:name, :nickname, :ap_id]
      |> Enum.each(fn (field) ->
        cs = User.remote_user_creation(Map.delete(@valid_remote, field))
        refute cs.valid?
      end)
    end

    test "it restricts some sizes" do
      [bio: 1000, name: 100]
      |> Enum.each(fn ({field, size}) ->
        string = String.pad_leading(".", size)
        cs = User.remote_user_creation(Map.put(@valid_remote, field, string))
        assert cs.valid?

        string = String.pad_leading(".", size + 1)
        cs = User.remote_user_creation(Map.put(@valid_remote, field, string))
        refute cs.valid?
      end)
    end
  end

  test "get a user by params" do
    user1 = insert(:user)
    user2 = insert(:user)
    user1_result = {:ok, user1}

    assert {:bad_request, "You need to specify screen_name or user_id"} == User.get_by_params(nil, nil)
    assert user1_result == User.get_by_params(nil, %{"user_id" => user1.id})
    assert user1_result == User.get_by_params(nil, %{"screen_name" => user1.nickname})
    assert user1_result == User.get_by_params(user1, nil)
    assert user1_result == User.get_by_params(user2, %{"user_id" => user1.id})
    assert user1_result == User.get_by_params(user2, %{"screen_name" => user1.nickname})
    assert {:not_found, "No user with such screen_name"} == User.get_by_params(nil, %{"screen_name" => "Satan"})
    assert {:not_found, "No user with such user_id"} == User.get_by_params(nil, %{"user_id" => 666})
  end
end
