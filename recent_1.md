# NavEye Supabase Person Memory Audit and Completion Summary

## 1. Current codebase status

The app remains a local-first, voice-first assistive application. The original on-device AI stack was not removed or replaced:
- YOLO/object detection remains active
- MobileFaceNet ONNX embedding generation remains active
- local SQLite person storage remains active
- manual registration remains active
- automatic person-memory flow remains optional and consent-gated

The Supabase layer is added as an additional cloud-sync layer, not as a replacement for local AI behavior.

## 2. Supabase initialization

The app initializes Supabase in the app entry point:

```dart
await Supabase.initialize(
  url: 'https://kfhnalgqqwehoquvwokk.supabase.co',
  publishableKey: 'sb_publishable_TUx95xZLtOiIu1KXnkt-ug_sZ9x_RoY',
);
```

This is in:
- lib/main.dart

The app uses the publishable key, not anonKey or a secret key.

## 3. Supabase image upload: confirmed actual implementation

The actual face image is uploaded to Supabase Storage in the cloud sync service:

```dart
final bytes = await file.readAsBytes();

await client.storage.from('person_faces').uploadBinary(
  storagePath,
  bytes,
  fileOptions: const FileOptions(
    upsert: true,
    contentType: 'image/jpeg',
  ),
);
```

This is in:
- lib/services/supabase_people_service.dart

This means the actual JPEG image bytes are uploaded to Supabase Storage.

## 4. Storage bucket used

Exact bucket:
- person_faces

Exact code:
- `client.storage.from('person_faces')`

The bucket must be private in production; the code was updated to use signed access rather than a public URL pattern.

## 5. Storage path generation

Exact path pattern:

```dart
final storagePath = 'people/$safeName-$timestamp-${p.basename(imagePath)}';
```

Example shape:
- `people/Person_1-1720000000000-nav_auto_memory_123456.jpg`

This is generated in:
- lib/services/supabase_people_service.dart

## 6. Local + cloud data model

### Local SQLite person schema
The local person table includes:
- id
- name
- image_path
- created_at
- embedding
- last_seen_at
- last_seen_latitude
- last_seen_longitude
- consent_status
- consent_timestamp
- sync_status
- storage_path
- image_url
- last_synced_at

This is in:
- lib/services/database_service.dart
- lib/models/person_model.dart

### Cloud people row fields written by Flutter
The app writes a row with:
- name
- storage_path
- image_url
- local_person_id
- created_at
- embedding_json
- sync_status
- source
- consent_status
- consent_timestamp
- last_seen_at
- last_seen_latitude
- last_seen_longitude

This is in:
- lib/services/supabase_people_service.dart

## 7. Automatic memory flow

The consented automatic person-memory flow works as follows:

1. Unknown person is detected
2. candidate frame is captured
3. consent is requested
4. if consent is granted:
   - local person record is created
   - embedding is extracted
   - local SQLite save occurs
   - local encounter is recorded
   - Supabase sync is attempted
5. if consent is denied:
   - no permanent biometric save
   - no image upload
   - no embedding upload

This is implemented in:
- lib/screens/main_ai/main_ai_screen.dart

Key methods:
- _requestAutoMemoryConsent
- _registerAutoMemoryCandidate
- _checkKnownPersonFromImage
- _updateAutoMemorySessionIfNeeded

## 8. Consent protection

Consent protection is active for the automatic-memory flow.

If the user says no, the flow does not permanently save the biometric data, and it does not upload the face image or embedding.

This is verified in:
- lib/screens/main_ai/main_ai_screen.dart

## 9. Local-first offline safety

The app remains safe when Supabase is unavailable.

Local data still persists:
- person record
- face image file
- embedding
- metadata
- encounter history

If the network is absent:
- the sync is deferred
- the local SQLite record remains intact
- the app continues to work locally

This is now tracked with sync states such as:
- pending
- synced
- failed

## 10. Private storage security audit

The active code does not use `getPublicUrl()` for face images.

It uses a private-storage pattern based on authenticated access and signed URLs:

```dart
final signed = await client.storage.from('person_faces').createSignedUrl(
  storagePath,
  60 * 60 * 24,
);
final imageUrl = signed;
```

This is in:
- lib/services/supabase_people_service.dart

This is the correct private-access direction for biometric face images.

Important dashboard requirement:
- The actual `person_faces` bucket must be configured as private in Supabase Storage.
- Row-level security and storage policies must allow only the authenticated session to access the data.

## 11. Pending sync behavior

A basic local-first pending sync layer has been added.

The app now keeps local records with sync status and defers uploads if connectivity is unavailable, instead of deleting local data or blocking detection.

This is implemented in:
- lib/models/person_model.dart
- lib/services/database_service.dart
- lib/services/supabase_people_service.dart

## 12. Actual image + embedding separation

The app handles the image and embedding separately:
- image bytes are uploaded to Storage
- embedding is stored in the cloud row as `embedding_json`

This avoids confusing the face image with the embedding vector.

## 13. Current final status

IMAGE STORAGE STATUS:
PARTIAL

Bucket:
person_faces

Image upload code:
client.storage.from('person_faces').uploadBinary(storagePath, bytes, fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'))

Storage path:
people/$safeName-$timestamp-${p.basename(imagePath)}

Database image column:
image_url

Automatic-memory upload:
YES

Offline queue:
PARTIAL

Consent protection:
YES

Embedding upload:
YES

Timestamp + GPS:
PARTIAL

## 14. What is still required externally

The code is complete on the Flutter side for the local-first + private cloud path, but the following external Supabase setup is still required in the dashboard:

1. Create the private `person_faces` bucket
2. Configure bucket policy for authenticated private access
3. Ensure the `people` table exists in PostgreSQL with the expected columns
4. Add table RLS rules for authenticated access only
5. Configure a cloud encounter table if encounter sync is required
6. Verify signed URLs function correctly under the bucket policy
7. Validate the end-to-end sync on a real authenticated Supabase session

## 15. Verification summary

Verified with fresh commands:
- `flutter analyze` -> successful, no issues found
- `flutter test` -> all tests passed
- `flutter build apk --debug` -> APK build succeeded

## 16. Final architecture summary

The final intended architecture remains:
- Android phone
- NavEye Flutter app
- local AI detection + recognition
- local SQLite person memory
- Supabase private Storage for face image upload
- Supabase PostgreSQL person metadata
- optional cloud sync after consent
- offline-safe local-first operation

This preserves the existing NavEye assistive app behavior while adding the missing private cloud person-memory layer.
