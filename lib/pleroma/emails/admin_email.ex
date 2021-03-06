# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.AdminEmail do
  @moduledoc "Admin emails"

  import Swoosh.Email

  alias Pleroma.Web.Router.Helpers

  defp instance_config, do: Pleroma.Config.get(:instance)
  defp instance_name, do: instance_config()[:name]
  defp instance_email, do: instance_config()[:email]

  defp user_url(user) do
    Helpers.o_status_url(Pleroma.Web.Endpoint, :feed_redirect, user.nickname)
  end

  def report(to, reporter, account, statuses, comment) do
    comment_html =
      if comment do
        "<p>Comment: #{comment}"
      else
        ""
      end

    statuses_html =
      if length(statuses) > 0 do
        statuses_list_html =
          statuses
          |> Enum.map(fn %{id: id} ->
            status_url = Helpers.o_status_url(Pleroma.Web.Endpoint, :notice, id)
            "<li><a href=\"#{status_url}\">#{status_url}</li>"
          end)
          |> Enum.join("\n")

        """
        <p> Statuses:
          <ul>
            #{statuses_list_html}
          </ul>
        </p>
        """
      else
        ""
      end

    html_body = """
    <p>Reported by: <a href="#{user_url(reporter)}">#{reporter.nickname}</a></p>
    <p>Reported Account: <a href="#{user_url(account)}">#{account.nickname}</a></p>
    #{comment_html}
    #{statuses_html}
    """

    new()
    |> to({to.name, to.email})
    |> from({instance_name(), instance_email()})
    |> reply_to({reporter.name, reporter.email})
    |> subject("#{instance_name()} Report")
    |> html_body(html_body)
  end
end
