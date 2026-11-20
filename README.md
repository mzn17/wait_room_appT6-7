# Waiting Room (Workshop 6 + multi-user)

Flutter + Supabase waiting queue with geolocation, connectivity monitoring,
offline registration (SQLite), automatic sync, pagination and Realtime.

The project also implements the two extensions requested on top of Workshop 6:

- **Multi-user**: Supabase Auth (email/password), one account per person,
  personal pending registrations, a `You` badge on your own queue entries.
- **Multi-tenant (optional feature)**: each account can create or join several
  waiting rooms. Every room has an isolated queue, its own per-room queue
  numbers, an invite code, and a member roster managed by the room owner.

## Workshop 6 checklist

| Feature | Status |
| --- | --- |
| Optional geolocation + permissions | Done |
| Network vs backend availability | Done |
| Offline registration in SQLite | Done |
| Automatic sync with retries | Done |
| Loading / empty / error / offline states | Done |
| Pagination + Realtime without duplicates | Done |
| Unit / widget tests | Done |

## Setup

1. `flutter pub get`
2. In Supabase, enable **Authentication > Providers > Email**.
   For local testing you can turn off **Confirm email**; otherwise confirm the
   account by email before signing in.
3. Run the whole `supabase/schema.sql` in the Supabase SQL Editor.
   The script is idempotent and upgrades an existing Workshop 6 database:
   legacy rows are moved to a `Legacy Room`.
4. Put your URL and public/publishable key in `lib/config/app_config.dart`
   (or use `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`).
5. Location permissions are already declared for Android / iOS.
6. `flutter test` then `flutter run`.

## How to use the multi-user / multi-tenant features

1. Create an account with a display name.
2. Create a room, or join one with its 8-character invite code.
3. Share the code from the room list to invite someone.
4. Open **Members** (people icon) to see the roster. The owner can add an
   existing account by email or remove a member.
5. Switch room from the top-right menu; each room keeps its own queue.
6. Sign out from the same menu. Pending offline registrations are scoped to
   the user and room, so another account on the same device never uploads them.

## Architecture

```
UI (screens/widgets)
  AuthScreen, RoomsScreen, QueueScreen, MembersScreen
        |
Providers
  AuthProvider, TenantProvider, QueueProvider, ConnectivityProvider
        |
Services
  AuthService, GeolocationService, ConnectivityService, SyncService
        |
Repositories
  TenantRepository, QueueRepository
        |
SQLite (LocalQueueStorage)  +  Supabase (Auth, PostgreSQL, Realtime, RLS)
```

Precise coordinates are stored in a private table nobody can read from the app.
Queue numbers are assigned by a server-side RPC, serialized per room, and
writes are only possible through security-definer functions. RLS restricts a
room's queue and roster to its members.
