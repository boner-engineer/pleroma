defmodule Pleroma.Web.ActivityPub.ActivityPubTest do
  use Pleroma.DataCase
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.Utils
  alias Pleroma.{Activity, Object, User}
  alias Pleroma.Builders.ActivityBuilder

  import Pleroma.Factory

  describe "insertion" do
    test "returns the activity if one with the same id is already in" do
      activity = insert(:note_activity)
      {:ok, new_activity}= ActivityPub.insert(activity.data)

      assert activity == new_activity
    end

    test "inserts a given map into the activity database, giving it an id if it has none." do
      data = %{
        "ok" => true
      }

      {:ok, %Activity{} = activity} = ActivityPub.insert(data)
      assert activity.data["ok"] == data["ok"]
      assert is_binary(activity.data["id"])

      given_id = "bla"
      data = %{
        "ok" => true,
        "id" => given_id
      }

      {:ok, %Activity{} = activity} = ActivityPub.insert(data)
      assert activity.data["ok"] == data["ok"]
      assert activity.data["id"] == given_id
    end

    test "adds an id to a given object if it lacks one and inserts it to the object database" do
      data = %{
        "object" => %{
          "ok" => true
        }
      }

      {:ok, %Activity{} = activity} = ActivityPub.insert(data)
      assert is_binary(activity.data["object"]["id"])
      assert %Object{} = Object.get_by_ap_id(activity.data["object"]["id"])
    end
  end

  describe "create activities" do
    test "removes doubled 'to' recipients" do
      {:ok, activity} = ActivityPub.create(["user1", "user1", "user2"], %User{ap_id: "1"}, "", %{})
      assert activity.data["to"] == ["user1", "user2"]
    end
  end

  describe "fetch activities for recipients" do
    test "retrieve the activities for certain recipients" do
      {:ok, activity_one} = ActivityBuilder.insert(%{"to" => ["someone"]})
      {:ok, activity_two} = ActivityBuilder.insert(%{"to" => ["someone_else"]})
      {:ok, _activity_three} = ActivityBuilder.insert(%{"to" => ["noone"]})

      activities = ActivityPub.fetch_activities(["someone", "someone_else"])
      assert length(activities) == 2
      assert activities == [activity_one, activity_two]
    end
  end

  describe "fetch activities in context" do
    test "retrieves activities that have a given context" do
      {:ok, activity} = ActivityBuilder.insert(%{"type" => "Create", "context" => "2hu"})
      {:ok, activity_two} = ActivityBuilder.insert(%{"type" => "Create", "context" => "2hu"})
      {:ok, _activity_three} = ActivityBuilder.insert(%{"type" => "Create", "context" => "3hu"})
      {:ok, _activity_four} = ActivityBuilder.insert(%{"type" => "Announce", "context" => "2hu"})
      activity_five = insert(:note_activity)
      user = insert(:user)

      {:ok, user} = User.block(user, %{ap_id: activity_five.data["actor"]})

      activities = ActivityPub.fetch_activities_for_context("2hu", %{"blocking_user" => user})
      assert activities == [activity_two, activity]
    end
  end

  test "doesn't return blocked activities" do
    activity_one = insert(:note_activity)
    activity_two = insert(:note_activity)
    user = insert(:user)
    {:ok, user} = User.block(user, %{ap_id: activity_one.data["actor"]})

    activities = ActivityPub.fetch_activities([], %{"blocking_user" => user})

    assert Enum.member?(activities, activity_two)
    refute Enum.member?(activities, activity_one)

    {:ok, user} = User.unblock(user, %{ap_id: activity_one.data["actor"]})

    activities = ActivityPub.fetch_activities([], %{"blocking_user" => user})

    assert Enum.member?(activities, activity_two)
    assert Enum.member?(activities, activity_one)

    activities = ActivityPub.fetch_activities([], %{"blocking_user" => nil})

    assert Enum.member?(activities, activity_two)
    assert Enum.member?(activities, activity_one)
  end

  describe "public fetch activities" do
    test "retrieves public activities" do
      activities = ActivityPub.fetch_public_activities

      %{public: public} = ActivityBuilder.public_and_non_public

      activities = ActivityPub.fetch_public_activities
      assert length(activities) == 1
      assert Enum.at(activities, 0) == public
    end

    test "retrieves a maximum of 20 activities" do
      activities = ActivityBuilder.insert_list(30)
      last_expected = List.last(activities)

      activities = ActivityPub.fetch_public_activities
      last = List.last(activities)

      assert length(activities) == 20
      assert last == last_expected
    end

    test "retrieves ids starting from a since_id" do
      activities = ActivityBuilder.insert_list(30)
      later_activities = ActivityBuilder.insert_list(10)
      since_id = List.last(activities).id
      last_expected = List.last(later_activities)

      activities = ActivityPub.fetch_public_activities(%{"since_id" => since_id})
      last = List.last(activities)

      assert length(activities) == 10
      assert last == last_expected
    end

    test "retrieves ids up to max_id" do
      _first_activities = ActivityBuilder.insert_list(10)
      activities = ActivityBuilder.insert_list(20)
      later_activities = ActivityBuilder.insert_list(10)
      max_id = List.first(later_activities).id
      last_expected = List.last(activities)

      activities = ActivityPub.fetch_public_activities(%{"max_id" => max_id})
      last = List.last(activities)

      assert length(activities) == 20
      assert last == last_expected
    end
  end

  describe "like an object" do
    test "adds a like activity to the db" do
      note_activity = insert(:note_activity)
      object = Object.get_by_ap_id(note_activity.data["object"]["id"])
      user = insert(:user)
      user_two = insert(:user)

      {:ok, like_activity, object} = ActivityPub.like(user, object)

      assert like_activity.data["actor"] == user.ap_id
      assert like_activity.data["type"] == "Like"
      assert like_activity.data["object"] == object.data["id"]
      assert like_activity.data["to"] == [User.ap_followers(user), note_activity.data["actor"]]
      assert like_activity.data["context"] == object.data["context"]
      assert object.data["like_count"] == 1
      assert object.data["likes"] == [user.ap_id]

      # Just return the original activity if the user already liked it.
      {:ok, same_like_activity, object} = ActivityPub.like(user, object)

      assert like_activity == same_like_activity
      assert object.data["likes"] == [user.ap_id]

      [note_activity] = Activity.all_by_object_ap_id(object.data["id"])
      assert note_activity.data["object"]["like_count"] == 1

      {:ok, _like_activity, object} = ActivityPub.like(user_two, object)
      assert object.data["like_count"] == 2
    end
  end

  describe "unliking" do
    test "unliking a previously liked object" do
      note_activity = insert(:note_activity)
      object = Object.get_by_ap_id(note_activity.data["object"]["id"])
      user = insert(:user)

      # Unliking something that hasn't been liked does nothing
      {:ok, object} = ActivityPub.unlike(user, object)
      assert object.data["like_count"] == 0

      {:ok, like_activity, object} = ActivityPub.like(user, object)
      assert object.data["like_count"] == 1

      {:ok, object} = ActivityPub.unlike(user, object)
      assert object.data["like_count"] == 0

      assert Repo.get(Activity, like_activity.id) == nil
    end
  end

  describe "announcing an object" do
    test "adds an announce activity to the db" do
      note_activity = insert(:note_activity)
      object = Object.get_by_ap_id(note_activity.data["object"]["id"])
      user = insert(:user)

      {:ok, announce_activity, object} = ActivityPub.announce(user, object)
      assert object.data["announcement_count"] == 1
      assert object.data["announcements"] == [user.ap_id]
      assert announce_activity.data["to"] == [User.ap_followers(user), note_activity.data["actor"]]
      assert announce_activity.data["object"] == object.data["id"]
      assert announce_activity.data["actor"] == user.ap_id
      assert announce_activity.data["context"] == object.data["context"]
    end
  end

  describe "uploading files" do
    test "copies the file to the configured folder" do
      file = %Plug.Upload{content_type: "image/jpg", path: Path.absname("test/fixtures/image.jpg"), filename: "an_image.jpg"}

      {:ok, %Object{} = object} = ActivityPub.upload(file)
      assert object.data["name"] == "an_image.jpg"
    end

    test "works with base64 encoded images" do
      file = %{
        "img" => data_uri()
      }

      {:ok, %Object{}} = ActivityPub.upload(file)
    end
  end

  describe "fetch the latest Follow" do
    test "fetches the latest Follow activity" do
      %Activity{data: %{"type" => "Follow"}} = activity = insert(:follow_activity)
      follower = Repo.get_by(User, ap_id: activity.data["actor"])
      followed = Repo.get_by(User, ap_id: activity.data["object"])

      assert activity == Utils.fetch_latest_follow(follower, followed)
    end
  end

  describe "following / unfollowing" do
    test "creates a follow activity" do
      follower = insert(:user)
      followed = insert(:user)

      {:ok, activity} = ActivityPub.follow(follower, followed)
      assert activity.data["type"] == "Follow"
      assert activity.data["actor"] == follower.ap_id
      assert activity.data["object"] == followed.ap_id
    end

    test "creates an undo activity for the last follow" do
      follower = insert(:user)
      followed = insert(:user)

      {:ok, follow_activity} = ActivityPub.follow(follower, followed)
      {:ok, activity} = ActivityPub.unfollow(follower, followed)

      assert activity.data["type"] == "Undo"
      assert activity.data["actor"] == follower.ap_id
      assert activity.data["object"] == follow_activity.data["id"]
    end
  end

  describe "deletion" do
    test "it creates a delete activity and deletes the original object" do
      note = insert(:note_activity)
      object = Object.get_by_ap_id(note.data["object"]["id"])
      {:ok, delete} = ActivityPub.delete(object)

      assert delete.data["type"] == "Delete"
      assert delete.data["actor"] == note.data["actor"]
      assert delete.data["object"] == note.data["object"]["id"]

      assert Repo.get(Activity, delete.id) != nil

      assert Repo.get(Object, object.id) == nil
    end
  end

  def data_uri do
    "data:image/jpeg;base64,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"
  end
end
