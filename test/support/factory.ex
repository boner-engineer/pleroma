defmodule Pleroma.Factory do
  use ExMachina.Ecto, repo: Pleroma.Repo
  alias Pleroma.Misc

  def user_factory do
    user = %Pleroma.User{
      name: sequence(:name, &"Test テスト User #{&1}"),
      email: sequence(:email, &"user#{&1}@example.com"),
      nickname: sequence(:nickname, &"nick#{&1}"),
      password_hash: Comeonin.Pbkdf2.hashpwsalt("test"),
      bio: sequence(:bio, &"Tester Number #{&1}"),
    }
    %{ user | ap_id: Pleroma.User.ap_id(user) }
  end

  def note_factory do
    text = sequence(:text, &"This is note #{&1}")

    user = insert(:user)
    data = %{
      "type" => "Note",
      "content" => text,
      "id" => Pleroma.Web.ActivityPub.ActivityPub.generate_object_id,
      "actor" => user.ap_id,
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "published_at" => Misc.make_date(),
      "likes" => [],
      "like_count" => 0,
      "context" => "2hu"
    }

    %Pleroma.Object{
      data: data
    }
  end

  def note_activity_factory do
    note = insert(:note)
    data = %{
      "id" => Pleroma.Web.ActivityPub.ActivityPub.generate_activity_id,
      "type" => "Create",
      "actor" => note.data["actor"],
      "to" => note.data["to"],
      "object" => note.data,
      "published_at" => Misc.make_date(),
      "context" => note.data["context"]
    }

    %Pleroma.Activity{
      data: data
    }
  end

  def like_activity_factory do
    note_activity = insert(:note_activity)
    user = insert(:user)

    data = %{
      "id" => Pleroma.Web.ActivityPub.ActivityPub.generate_activity_id,
      "actor" => user.ap_id,
      "type" => "Like",
      "object" => note_activity.data["object"]["id"],
      "published_at" => Misc.make_date()
    }

    %Pleroma.Activity{
      data: data
    }
  end

  def follow_activity_factory do
    follower = insert(:user)
    followed = insert(:user)

    data = %{
      "id" => Pleroma.Web.ActivityPub.ActivityPub.generate_activity_id,
      "actor" => follower.ap_id,
      "type" => "Follow",
      "object" => followed.ap_id,
      "published_at" => Misc.make_date()
    }

    %Pleroma.Activity{
      data: data
    }
  end

  def websub_subscription_factory do
    %Pleroma.Web.Websub.WebsubServerSubscription{
      topic: "http://example.org",
      callback: "http://example/org/callback",
      secret: "here's a secret",
      valid_until: NaiveDateTime.add(NaiveDateTime.utc_now, 100),
      state: "requested"
    }
  end

  def websub_client_subscription_factory do
    %Pleroma.Web.Websub.WebsubClientSubscription{
      topic: "http://example.org",
      secret: "here's a secret",
      valid_until: nil,
      state: "requested",
      subscribers: []
    }
  end
end
