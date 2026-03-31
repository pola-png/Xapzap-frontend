Block Filter + Push Notification Deploy Notes

This function package now handles:

- existing block-filter/feed routes
- account deletion route
- AdMob sync routes
- FCM push dispatch for notification rows

Required Appwrite function event

- Add a table-row create event for the notifications table to this same function.
- Use the notifications row create event for your project/database/table.

Expected function environment variables

- `APPWRITE_FUNCTION_API_KEY` or `APPWRITE_API_KEY`
- `APPWRITE_FUNCTION_API_ENDPOINT` or `APPWRITE_ENDPOINT`
- `APPWRITE_FUNCTION_PROJECT_ID` or `APPWRITE_PROJECT_ID`
- `XAPZAP_DATABASE_ID`
- `XAPZAP_NOTIFICATIONS_TABLE_ID`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`

Firebase notes

- `FIREBASE_PRIVATE_KEY` must preserve line breaks. If entered as a single line in Appwrite env vars, `\n` is supported and converted back at runtime.

Profile schema fields expected by push delivery

- `fcmToken`
- `pushNotificationsEnabled`
- `pushPlatform`
- `pushUpdatedAt`

Manual test route

- The same function also supports an explicit route:
- `/v1/notifications/dispatch`

Minimal JSON body example

```json
{
  "notification": {
    "$id": "notif_123",
    "userId": "user_123",
    "title": "New follower",
    "body": "Jane started following you.",
    "type": "follow",
    "actorAvatar": "https://example.com/avatar.jpg",
    "actionUrl": "/notifications"
  }
}
```
