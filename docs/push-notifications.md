# Push notifications

The console receives Firebase Cloud Messaging (FCM) pushes from `server_hub`.
Android 8+ fixes sound and importance **per channel**, so the app exposes three
channels and the hub selects one by id. Channel ids are a contract: never rename
them, because installed users keep the settings of channels they already have.

## Channels

| Channel id | Importance | Sound | Vibration | Use for |
| --- | --- | --- | --- | --- |
| `hub_critical` | high | yes | yes | service down, crash, disk full, failed action |
| `hub_alerts` | high | yes | yes | chat replies, warnings, routine operator alerts |
| `hub_silent` | low | no | no | background sync, progress, technical noise |

`hub_alerts` is also the manifest default (`default_notification_channel_id`),
so a push without an explicit channel still rings.

## Message shape

```jsonc
{
  "notification": {
    "title": "Агент ответил",
    "body": "Сборка прошла, 3 замечания",
    "android": { "channel_id": "hub_alerts" }
  },
  "data": {
    "route": "chat",
    "entity_id": "ses_abc123",
    "type": "chat.message",
    "severity": "alert",
    "notification_id": "42"
  }
}
```

- `notification.android.channel_id` — preferred severity selector. Use
  `hub_critical` / `hub_alerts` / `hub_silent`.
- `data.severity` — fallback when the channel id is omitted:
  `critical` / `alert` / `quiet` (aliases: `crash`, `fatal`, `emergency`;
  `important`, `warning`, `high`, `default`; `silent`, `low`, `info`, `debug`,
  `background`).
- `data.route` — tab to open on tap: `chat`, `status`, `terminal`, `control`,
  `settings` (leading `/` and free-form values such as `assistant` are
  tolerated).
- `data.entity_id` — what to focus after opening the tab (chat session id,
  service name, log source). Optional today, kept for deep links.
- `data.type` — used as a route fallback, e.g. `chat.message`, `service.down`,
  `log.line`.
- `data.notification_id` — optional stable id; otherwise the app derives one
  from the FCM message id.
- Data-only pushes (no `notification` block) are supported for background
  work. The app draws them itself, so include `data.title` and `data.body`;
  without them the push is treated as an invisible liveness ping.

Unknown severity falls back to `hub_alerts`; an unknown/missing route opens
`status`. A malformed payload never breaks tap handling.

## App behaviour

- **Foreground**: Android does not show FCM notification payloads while the app
  is visible, so the app draws a local notification on the same channel.
  Duplicate deliveries of the same `messageId` are ignored.
- **Background / terminated**: Android draws the notification from the
  `notification` block using `channel_id`. A data-only message is drawn by the
  background isolate.
- **Tap**: opens the requested tab. This works for system-drawn FCM
  notifications, locally drawn foreground notifications, and a cold start from
  a notification.

## Verification checklist

- [ ] `hub_critical` rings and vibrates; `hub_silent` is silent.
- [ ] Foreground push appears once (no duplicate on reconnect/re-delivery).
- [ ] Tap opens `CHAT` for `route: "chat"`, `STATUS` for `route: "status"`.
- [ ] Cold start from a notification lands on the requested tab.
- [ ] Data-only push without title/body shows nothing and does not crash.
- [ ] A push without `channel_id` still uses `hub_alerts` and rings.

## Backend follow-up

`server_hub` must map its event classes onto the three channel ids above,
include `route` / `entity_id` / `type` in `data`, and keep this document (and
its own API docs) in sync when the contract changes.
