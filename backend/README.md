# LineSight API (local development)

The API supports account registration/login, workspace creation and invitations, role checked production jobs, member listing, human resolved exceptions, and private photo evidence with original and Canny preview endpoints. The review preview never assigns a pass/fail verdict. The Flutter app connects to this service when a team workspace is selected; the existing device workspace remains separate.

## Run locally

From the repository root in PowerShell:

```powershell
$env:DJANGO_SETTINGS_MODULE = 'linesight.local_settings'
python backend/manage.py migrate --run-syncdb
python backend/manage.py runserver 0.0.0.0:8000
```

The local settings use SQLite and a development signing key. They are for development and repeatable local verification only. On the Android emulator, connect to `http://10.0.2.2:8000/api/v1/`. For another host, enter the HTTPS service address supplied by the workspace administrator. HTTP is accepted only in debug builds; release builds require HTTPS. Register at `POST /api/v1/auth/register/`, sign in at `/api/v1/auth/login/`, and send the returned bearer token on authenticated requests. Create a workspace at `/api/v1/workspaces/create/`. Upload a multipart `image` field to a job's `/evidence/` endpoint.

To supply the local API address in a debug run without displaying it in the normal interface:

```powershell
flutter run --dart-define=LINESIGHT_API_BASE_URL=http://10.0.2.2:8000/api/v1/
```

Run the API checks with:

```powershell
$env:DJANGO_SETTINGS_MODULE = 'linesight.local_settings'
python backend/manage.py test collaboration
```

## Current boundary

The team workspace screen uses this API for shared workspaces and jobs. Device workspaces remain available independently, and there is no automatic upload or merge. Team sign-in is held in memory for the current app session; users sign in again after a restart or token expiry. The production settings in `linesight/settings.py` still target PostgreSQL tenant schemas and the allauth JWT flow; those tenant models, migrations, production URL modules, and deployment configuration have not been completed or verified. Do not use the local signing key, local SQLite settings, or development media path for deployment.
