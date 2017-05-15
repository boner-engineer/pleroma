defmodule Pleroma.Web.TwitterAPI.UserViewTest do
  use Pleroma.DataCase

  alias Pleroma.User
  alias Pleroma.Web.TwitterAPI.UserView
  alias Pleroma.Builders.UserBuilder

  import Pleroma.Factory

  setup do
    user = insert(:user)
    [user: user]
  end

  test "A user with an avatar object", %{user: user} do
    image = "image"
    user = %{ user | avatar: %{ "url" => [%{"href" => image}] }}
    represented = UserView.render("show.json", %{user: user})
    assert represented["profile_image_url"] == image
  end

  test "A user" do
    note_activity = insert(:note_activity)
    user = User.get_cached_by_ap_id(note_activity.data["actor"])
    follower = insert(:user)
    second_follower = insert(:user)

    User.follow(follower, user)
    User.follow(second_follower, user)
    User.follow(user, follower)

    user = Repo.get!(User, user.id)

    image = "https://placehold.it/48x48"

    represented = %{
      "id" => user.id,
      "name" => user.name,
      "screen_name" => user.nickname,
      "description" => user.bio,
      "favourites_count" => 0,
      "statuses_count" => 1,
      "friends_count" => 1,
      "followers_count" => 2,
      "profile_image_url" => image,
      "profile_image_url_https" => image,
      "profile_image_url_profile_size" => image,
      "profile_image_url_original" => image,
      "following" => false,
      "rights" => %{},
      "statusnet_profile_url" => user.ap_id
    }

    assert represented == UserView.render("show.json", %{user: user})
  end

  test "A user for a given other follower", %{user: user} do
    {:ok, follower} = UserBuilder.insert(%{following: [User.ap_followers(user)]})
    image = "https://placehold.it/48x48"
    represented = %{
      "id" => user.id,
      "name" => user.name,
      "screen_name" => user.nickname,
      "description" => user.bio,
      "favourites_count" => 0,
      "statuses_count" => 0,
      "friends_count" => 0,
      "followers_count" => 1,
      "profile_image_url" => image,
      "profile_image_url_https" => image,
      "profile_image_url_profile_size" => image,
      "profile_image_url_original" => image,
      "following" => true,
      "rights" => %{},
      "statusnet_profile_url" => user.ap_id
    }

    assert represented == UserView.render("show.json", %{user: user, for: follower})
  end
end
