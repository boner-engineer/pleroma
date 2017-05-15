defmodule Pleroma.Web.OStatus do
  @httpoison Application.get_env(:pleroma, :httpoison)

  import Ecto.Query
  import Pleroma.Web.XML
  require Logger

  alias Pleroma.{Repo, User, Web, Object, Activity}
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.{WebFinger, Websub}

  def feed_path(user) do
    "#{user.ap_id}/feed.atom"
  end

  def pubsub_path(user) do
    "#{Web.base_url}/push/hub/#{user.nickname}"
  end

  def salmon_path(user) do
    "#{user.ap_id}/salmon"
  end

  def handle_incoming(xml_string) do
    doc = parse_document(xml_string)
    entries = :xmerl_xpath.string('//entry', doc)

    activities = Enum.map(entries, fn (entry) ->
      {:xmlObj, :string, object_type} = :xmerl_xpath.string('string(/entry/activity:object-type[1])', entry)
      {:xmlObj, :string, verb} = :xmerl_xpath.string('string(/entry/activity:verb[1])', entry)

      case verb do
        'http://activitystrea.ms/schema/1.0/share' ->
          with {:ok, activity, retweeted_activity} <- handle_share(entry, doc), do: [activity, retweeted_activity]
        'http://activitystrea.ms/schema/1.0/favorite' ->
          with {:ok, activity, favorited_activity} <- handle_favorite(entry, doc), do: [activity, favorited_activity]
        _ ->
          case object_type do
            'http://activitystrea.ms/schema/1.0/note' ->
              with {:ok, activity} <- handle_note(entry, doc), do: activity
            'http://activitystrea.ms/schema/1.0/comment' ->
              with {:ok, activity} <- handle_note(entry, doc), do: activity
            _ ->
              Logger.error("Couldn't parse incoming document")
              nil
          end
      end
    end)
    {:ok, activities}
  end

  def make_share(entry, doc, retweeted_activity) do
    with {:ok, actor} <- find_make_or_update_user(doc),
         %Object{} = object <- Object.get_by_ap_id(retweeted_activity.data["object"]["id"]),
         id when not is_nil(id) <- string_from_xpath("/entry/id", entry),
         {:ok, activity, _object} = ActivityPub.announce(actor, object, id, false) do
      {:ok, activity}
    end
  end

  def handle_share(entry, doc) do
    with [object] <- :xmerl_xpath.string('/entry/activity:object', entry),
         {:ok, retweeted_activity} <-  handle_note(object, object),
         {:ok, activity} <- make_share(entry, doc, retweeted_activity) do
      {:ok, activity, retweeted_activity}
    else
      e -> {:error, e}
    end
  end

  def make_favorite(entry, doc, favorited_activity) do
    with {:ok, actor} <- find_make_or_update_user(doc),
         %Object{} = object <- Object.get_by_ap_id(favorited_activity.data["object"]["id"]),
         id when not is_nil(id) <- string_from_xpath("/entry/id", entry),
         {:ok, activity, _object} = ActivityPub.like(actor, object, id, false) do
      {:ok, activity}
    end
  end

  def get_or_try_fetching(entry) do
    with id when not is_nil(id) <- string_from_xpath("//activity:object[1]/id", entry),
         %Activity{} = activity <- Activity.get_create_activity_by_object_ap_id(id) do
      {:ok, activity}
    else _e ->
        with href when not is_nil(href) <- string_from_xpath("//activity:object[1]/link[@type=\"text/html\"]/@href", entry),
             {:ok, [favorited_activity]} <- fetch_activity_from_html_url(href) do
          {:ok, favorited_activity}
        end
    end
  end

  def handle_favorite(entry, doc) do
    with {:ok, favorited_activity} <- get_or_try_fetching(entry),
         {:ok, activity} <- make_favorite(entry, doc, favorited_activity) do
      {:ok, activity, favorited_activity}
    else
      e -> {:error, e}
    end
  end

  def get_attachments(entry) do
    xpath = :xmerl_xpath.string('/entry/link[@rel="enclosure"]', entry)
    xpath
    |> Enum.map(fn (enclosure) ->
      with href when not is_nil(href) <- string_from_xpath("/link/@href", enclosure),
           type when not is_nil(type) <- string_from_xpath("/link/@type", enclosure) do
        %{
          "type" => "Attachment",
          "url" => [%{
                       "type" => "Link",
                       "mediaType" => type,
                       "href" => href
                    }]
        }
      end
    end)
    |> Enum.filter(&(&1))
  end

  def handle_note(entry, doc \\ nil) do
    content_html = string_from_xpath("//content[1]", entry)

    [author] = :xmerl_xpath.string('//author[1]', doc)
    {:ok, actor} = find_make_or_update_user(author)
    in_reply_to = string_from_xpath("//thr:in-reply-to[1]/@ref", entry)

    if !Object.get_cached_by_ap_id(in_reply_to) do
      in_reply_to_href = string_from_xpath("//thr:in-reply-to[1]/@href", entry)
      if in_reply_to_href do
        fetch_activity_from_html_url(in_reply_to_href)
      end
    end

    context = (string_from_xpath("//ostatus:conversation[1]", entry) || "") |> String.trim

    attachments = get_attachments(entry)

    context = with %{data: %{"context" => context}} <- Object.get_cached_by_ap_id(in_reply_to) do
                context
              else _e ->
                if String.length(context) > 0 do
                  context
                else
                  ActivityPub.generate_context_id
                end
              end

    to = [
      "https://www.w3.org/ns/activitystreams#Public",
      User.ap_followers(actor)
    ]
    xpath = :xmerl_xpath.string('//link[@rel="mentioned" and @ostatus:object-type="http://activitystrea.ms/schema/1.0/person"]', entry)
    mentions = xpath
    |> Enum.map(fn(person) -> string_from_xpath("@href", person) end)

    to = to ++ mentions

    date = string_from_xpath("//published", entry)
    id = string_from_xpath("//id", entry)

    object = %{
      "id" => id,
      "type" => "Note",
      "to" => to,
      "content" => content_html,
      "published" => date,
      "context" => context,
      "actor" => actor.ap_id,
      "attachment" => attachments
    }

    object = if in_reply_to do
      Map.put(object, "inReplyTo", in_reply_to)
    else
      object
    end

    # TODO: Bail out sooner and use transaction.
    if Object.get_by_ap_id(id) do
      {:ok, Activity.get_create_activity_by_object_ap_id(id)}
    else
      ActivityPub.create(to, actor, context, object, %{}, date, false)
    end
  end

  def find_make_or_update_user(doc) do
    uri = string_from_xpath("//author/uri[1]", doc)
    with {:ok, user} <- find_or_make_user(uri) do
      avatar = make_avatar_object(doc)
      if !user.local && user.avatar != avatar do
        change = Ecto.Changeset.change(user, %{avatar: avatar})
        Repo.update(change)
      else
        {:ok, user}
      end
    end
  end

  def find_or_make_user(uri) do
    query = from user in User,
      where: user.ap_id == ^uri

    user = Repo.one(query)

    if is_nil(user) do
      make_user(uri)
    else
      {:ok, user}
    end
  end

  def make_user(uri) do
    with {:ok, info} <- gather_user_info(uri) do
      data = %{
        name: info["name"],
        nickname: info["nickname"] <> "@" <> info["host"],
        ap_id: info["uri"],
        info: info,
        avatar: info["avatar"]
      }
      cs = User.remote_user_creation(data)
      Repo.insert(cs)
    end
  end

  # TODO: Just takes the first one for now.
  def make_avatar_object(author_doc) do
    href = string_from_xpath("//author[1]/link[@rel=\"avatar\"]/@href", author_doc)
    type = string_from_xpath("//author[1]/link[@rel=\"avatar\"]/@type", author_doc)

    if href do
      %{
        "type" => "Image",
        "url" =>
          [%{
              "type" => "Link",
              "mediaType" => type,
              "href" => href
           }]
      }
    else
      nil
    end
  end

  def gather_user_info(username) do
    with {:ok, webfinger_data} <- WebFinger.finger(username),
         {:ok, feed_data} <- Websub.gather_feed_data(webfinger_data["topic"]) do
      {:ok, webfinger_data |> Map.merge(feed_data) |> Map.put("fqn", username)}
    else e ->
      Logger.debug(fn -> "Couldn't gather info for #{username}" end)
      {:error, e}
    end
  end

  # Regex-based 'parsing' so we don't have to pull in a full html parser
  # It's a hack anyway. Maybe revisit this in the future
  @mastodon_regex ~r/<link href='(.*)' rel='alternate' type='application\/atom\+xml'>/
  @gs_regex ~r/<link title=.* href="(.*)" type="application\/atom\+xml" rel="alternate">/
  @gs_classic_regex ~r/<link rel="alternate" href="(.*)" type="application\/atom\+xml" title=.*>/
  def get_atom_url(body) do
    cond do
      Regex.match?(@mastodon_regex, body) ->
        [[_, match]] = Regex.scan(@mastodon_regex, body)
        {:ok, match}
      Regex.match?(@gs_regex, body) ->
        [[_, match]] = Regex.scan(@gs_regex, body)
        {:ok, match}
      Regex.match?(@gs_classic_regex, body) ->
        [[_, match]] = Regex.scan(@gs_classic_regex, body)
        {:ok, match}
      true ->
        Logger.debug(fn -> "Couldn't find atom link in #{inspect(body)}" end)
        {:error, "Couldn't find the atom link"}
    end
  end

  def fetch_activity_from_html_url(url) do
    with {:ok, %{body: body}} <- @httpoison.get(url, [], follow_redirect: true),
         {:ok, atom_url} <- get_atom_url(body),
         {:ok, %{status_code: code, body: body}} when code in 200..299 <- @httpoison.get(atom_url, [], follow_redirect: true) do
      handle_incoming(body)
    end
  end
end
