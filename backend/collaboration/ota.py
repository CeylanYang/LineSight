"""Read-only OTA distribution. Publishing is an SSH-only operator action.

Artifacts are public signed application code; no account data or upload API.
The client verifies the pinned Ed25519 key and SHA-256 before installation.
"""
import os
from pathlib import Path
import re

from django.http import FileResponse, Http404, HttpResponse, JsonResponse
from django.views.decorators.http import require_GET


@require_GET
def runtime_config(request):
    target = Path(os.environ.get('LINESIGHT_RUNTIME_CONFIG', '/var/lib/linesight/runtime/app-config.json'))
    if not target.is_file():
        return HttpResponse(status=204, headers={'Cache-Control': 'no-store'})
    if target.stat().st_size > 256 * 1024:
        return HttpResponse(status=503)
    return FileResponse(target.open('rb'), content_type='application/json', headers={
        'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff'})


@require_GET
def artifact(request, track, base, abi, name):
    if (track not in {"preview", "production"} or not 1 <= base <= 2147483647
            or abi not in {"arm64-v8a", "x86_64"}
            or not re.fullmatch(r"manifest\.json|[a-f0-9]{64}\.so", name)):
        raise Http404
    root = Path(os.environ.get("LINESIGHT_OTA_DIR", "/var/lib/linesight/ota"))
    folder = root / track / str(base) / abi
    target = folder / name
    # Refuse symlink escapes even if an operator misconfigures storage.
    if not target.resolve().is_relative_to(root.resolve()):
        raise Http404
    if not target.is_file():
        if name == "manifest.json":
            response = HttpResponse(status=204)
            response["Cache-Control"] = "no-store"
            return response
        raise Http404
    if name == "manifest.json":
        if target.stat().st_size > 16384:
            return JsonResponse({"detail": "Unavailable"}, status=503)
        response = FileResponse(target.open("rb"), content_type="application/json")
        response["Cache-Control"] = "no-store"
    else:
        response = FileResponse(target.open("rb"), content_type="application/octet-stream")
        response["Cache-Control"] = "public, max-age=31536000, immutable"
    response["X-Content-Type-Options"] = "nosniff"
    return response
