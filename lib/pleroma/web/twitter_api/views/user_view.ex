defmodule Pleroma.Web.TwitterAPI.UserView do
  use Pleroma.Web, :view
  alias Pleroma.User

  def render("show.json", %{user: user = %User{}} = assigns) do
    image = User.avatar_url(user)
    following = if assigns[:for] do
      User.following?(assigns[:for], user)
    else
      false
    end

    user_info = User.get_cached_user_info(user)

    %{
      "description" => user.bio,
      "favourites_count" => 0,
      "followers_count" => user_info[:follower_count],
      "following" => following,
      "friends_count" => user_info[:following_count],
      "id" => user.id,
      "name" => user.name,
      "profile_image_url" => image,
      "profile_image_url_https" => image,
      "profile_image_url_profile_size" => image,
      "profile_image_url_original" => image,
      "rights" => %{},
      "screen_name" => user.nickname,
      "statuses_count" => user_info[:note_count],
      "statusnet_profile_url" => user.ap_id
    }
  end

  def render("short.json", %{user: %User{
                               nickname: nickname, id: id, ap_id: ap_id, name: name
                           }}) do
    %{
      "fullname" => name,
      "id" => id,
      "ostatus_uri" => ap_id,
      "profile_url" => ap_id,
      "screen_name" => nickname
    }
  end
end
