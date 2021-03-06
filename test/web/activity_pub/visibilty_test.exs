defmodule Pleroma.Web.ActivityPub.VisibilityTest do
  use Pleroma.DataCase

  alias Pleroma.Web.CommonAPI
  alias Pleroma.Web.ActivityPub.Visibility
  import Pleroma.Factory

  setup do
    user = insert(:user)
    mentioned = insert(:user)
    following = insert(:user)
    unrelated = insert(:user)
    {:ok, following} = Pleroma.User.follow(following, user)

    {:ok, public} =
      CommonAPI.post(user, %{"status" => "@#{mentioned.nickname}", "visibility" => "public"})

    {:ok, private} =
      CommonAPI.post(user, %{"status" => "@#{mentioned.nickname}", "visibility" => "private"})

    {:ok, direct} =
      CommonAPI.post(user, %{"status" => "@#{mentioned.nickname}", "visibility" => "direct"})

    {:ok, unlisted} =
      CommonAPI.post(user, %{"status" => "@#{mentioned.nickname}", "visibility" => "unlisted"})

    %{
      public: public,
      private: private,
      direct: direct,
      unlisted: unlisted,
      user: user,
      mentioned: mentioned,
      following: following,
      unrelated: unrelated
    }
  end

  test "is_direct?", %{public: public, private: private, direct: direct, unlisted: unlisted} do
    assert Visibility.is_direct?(direct)
    refute Visibility.is_direct?(public)
    refute Visibility.is_direct?(private)
    refute Visibility.is_direct?(unlisted)
  end

  test "is_public?", %{public: public, private: private, direct: direct, unlisted: unlisted} do
    refute Visibility.is_public?(direct)
    assert Visibility.is_public?(public)
    refute Visibility.is_public?(private)
    assert Visibility.is_public?(unlisted)
  end

  test "is_private?", %{public: public, private: private, direct: direct, unlisted: unlisted} do
    refute Visibility.is_private?(direct)
    refute Visibility.is_private?(public)
    assert Visibility.is_private?(private)
    refute Visibility.is_private?(unlisted)
  end

  test "visible_for_user?", %{
    public: public,
    private: private,
    direct: direct,
    unlisted: unlisted,
    user: user,
    mentioned: mentioned,
    following: following,
    unrelated: unrelated
  } do
    # All visible to author

    assert Visibility.visible_for_user?(public, user)
    assert Visibility.visible_for_user?(private, user)
    assert Visibility.visible_for_user?(unlisted, user)
    assert Visibility.visible_for_user?(direct, user)

    # All visible to a mentioned user

    assert Visibility.visible_for_user?(public, mentioned)
    assert Visibility.visible_for_user?(private, mentioned)
    assert Visibility.visible_for_user?(unlisted, mentioned)
    assert Visibility.visible_for_user?(direct, mentioned)

    # DM not visible for just follower

    assert Visibility.visible_for_user?(public, following)
    assert Visibility.visible_for_user?(private, following)
    assert Visibility.visible_for_user?(unlisted, following)
    refute Visibility.visible_for_user?(direct, following)

    # Public and unlisted visible for unrelated user

    assert Visibility.visible_for_user?(public, unrelated)
    assert Visibility.visible_for_user?(unlisted, unrelated)
    refute Visibility.visible_for_user?(private, unrelated)
    refute Visibility.visible_for_user?(direct, unrelated)
  end
end
