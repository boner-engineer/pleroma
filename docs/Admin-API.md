# Admin API

Authentication is required and the user must be an admin.

## `/api/pleroma/admin/users`

### List users

- Method `GET`
- Response:

```JSON
[
    {
        "deactivated": bool,
        "id": integer,
        "nickname": string
    },
    ...
]
```

## `/api/pleroma/admin/user`

### Remove a user

- Method `DELETE`
- Params:
  - `nickname`
- Response: User’s nickname

### Create a user

- Method: `POST`
- Params:
  - `nickname`
  - `email`
  - `password`
- Response: User’s nickname

## `/api/pleroma/admin/users/:nickname/toggle_activation`

### Toggle user activation

- Method: `PATCH`
- Params:
  - `nickname`
- Response: User’s object

```JSON
{
    "deactivated": bool,
    "id": integer,
    "nickname": string
}
```

## `/api/pleroma/admin/users/tag`

### Tag a list of users

- Method: `PUT`
- Params:
  - `nickname`
  - `tags`

### Untag a list of users

- Method: `DELETE`
- Params:
  - `nickname`
  - `tags`

## `/api/pleroma/admin/permission_group/:nickname`

### Get user user permission groups membership

- Method: `GET`
- Params: none
- Response:

```JSON
{
    "is_moderator": bool,
    "is_admin": bool
}
```

## `/api/pleroma/admin/permission_group/:nickname/:permission_group`

Note: Available `:permission_group` is currently moderator and admin. 404 is returned when the permission group doesn’t exist.

### Get user user permission groups membership

- Method: `GET`
- Params: none
- Response:

```JSON
{
    "is_moderator": bool,
    "is_admin": bool
}
```

### Add user in permission group

- Method: `POST`
- Params: none
- Response:
  - On failure: `{"error": "…"}`
  - On success: JSON of the `user.info`

### Remove user from permission group

- Method: `DELETE`
- Params: none
- Response:
  - On failure: `{"error": "…"}`
  - On success: JSON of the `user.info`
- Note: An admin cannot revoke their own admin status.

## `/api/pleroma/admin/activation_status/:nickname`

### Active or deactivate a user

- Method: `PUT`
- Params:
  - `nickname`
  - `status` BOOLEAN field, false value means deactivation.

## `/api/pleroma/admin/relay`

### Follow a Relay

- Methods: `POST`
- Params:
  - `relay_url`
- Response:
  - On success: URL of the followed relay

### Unfollow a Relay

- Methods: `DELETE`
- Params:
  - `relay_url`
- Response:
  - On success: URL of the unfollowed relay

## `/api/pleroma/admin/invite_token`

### Get a account registeration invite token

- Methods: `GET`
- Params: none
- Response: invite token (base64 string)

## `/api/pleroma/admin/email_invite`

### Sends registration invite via email

- Methods: `POST`
- Params:
  - `email`
  - `name`, optionnal

## `/api/pleroma/admin/password_reset`

### Get a password reset token for a given nickname

- Methods: `GET`
- Params: none
- Response: password reset token (base64 string)
