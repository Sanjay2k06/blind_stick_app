# Recent NavEye additions and Supabase details

## Overview
This document captures the recent changes made to the existing NavEye Flutter app without replacing the current on-device AI/voice-first functionality.

The app remains a local-first assistive system for visually impaired users, with voice as the primary control method and local face recognition preserved.

## Core architecture
- Android phone -> NavEye Flutter app -> local AI processing + voice assistance
- Local face recognition remains active using MobileFaceNet ONNX
- Local SQLite database continues to store people and embeddings
- Supabase is added as an optional cloud sync layer for storage + metadata
- Cloud sync is additive and should not block the existing local recognition flow

## Supabase setup
Project URL:
- https://kfhnalgqqwehoquvwokk.supabase.co

Initialization used:
```dart
await Supabase.initialize(
  url: 'https://kfhnalgqqwehoquvwokk.supabase.co',
  publishableKey: 'sb_publishable_TUx95xZLtOiIu1KXnkt-ug_sZ9x_RoY',
);
```

Important rules followed:
- Used the Supabase publishable key, not the anon key
- Used the required v2 initialization style
- Did not proceed to database/storage integration before confirming the local app architecture
- Kept existing AI functionality intact

## Storage design
The cloud storage layer is used for person face photos only.

Storage bucket:
- `person_faces`

Example object path pattern:
- `people/<safe_name>-<timestamp>-<filename>.jpg`

This uploads the person image captured during registration.

## People table design
The app syncs person metadata into a `people` table with fields such as:
- `id`
- `name`
- `image_url`
- `local_person_id`
- `created_at`
- `embedding_json`
- `sync_status`
- `source`

Upsert behavior:
- `upsert(..., onConflict: 'local_person_id')`
- This preserves the relationship between the local SQLite record and the cloud record

## Local people flow preserved
The local person registration pipeline remains intact:
1. Capture photos in people capture flow
2. Enter name in people name screen
3. Save local record in SQLite
4. Generate face embedding from captured photos
5. Update local embedding in SQLite
6. Refresh local known people set
7. Attempt optional cloud sync after local save

This means the app continues to work even when the cloud layer is unavailable.

## Offline behavior
The implementation is designed to be safe offline:
- Local DB save happens first
- Local embedding generation happens first
- Cloud upload is attempted afterward
- If Supabase fails, the app logs the issue and continues without crashing
- Device recognition continues working using local data

## RLS / auth status
Current status:
- The app is initialized with the correct published Supabase client configuration
- No authentication flow was forced into the app for this stage
- The cloud schema and storage bucket must still have proper Row Level Security and bucket policies configured before production use

This is a requirement for production safety, but it does not interfere with the app’s local-first operation.

## Local data preservation
No local recognition or local person data was removed.

The design keeps the following intact:
- SQLite people table
- local embedding storage
- local face recognition model
- local voice-first UI/UX flow
- existing recognition logic using MobileFaceNet and local matching

## Recent implementation details
The recent implementation includes:
- Supabase initialization using the publishable key
- a dedicated `SupabasePeopleService`
- safe upload of face images to Supabase Storage
- safe upsert of person metadata into the cloud `people` table
- local-only fallback when cloud sync fails
- no modification of the original object detection or local recognition flow

## Files involved in the recent cloud sync work
- `lib/main.dart`
- `lib/screens/people/people_enter_name_screen.dart`
- `lib/services/supabase_people_service.dart`
- `lib/services/database_service.dart`
- `lib/models/person_model.dart`

## Verification status
The app was verified after the implementation with the required Flutter checks:

- `flutter analyze` -> successful, no issues found
- `flutter build apk --debug` -> successful APK generated

Build command output confirmed success:
- `Built build\app\outputs\flutter-apk\app-debug.apk`

## Notes
This is intentionally not a rewrite of the app. It is a cloud extension layered over the existing NavEye project, keeping the current assistive app behavior and local AI pipeline intact.

The final intended architecture is:
- Android phone
- NavEye Flutter app
- Supabase Storage for face photos
- Supabase PostgreSQL (or equivalent table backend) for person metadata
- On-device MobileFaceNet for local recognition and fast offline operation
