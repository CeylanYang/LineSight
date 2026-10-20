from django.contrib import admin
from django.http import JsonResponse
from django.urls import include, path

from allauth.headless import urls as headless_urls


def root(request):
    return JsonResponse(
        {
            "name": "LineSight",
            "api": "v1",
            "auth": "/_allauth/app/v1/",
            "workspaces": "/api/v1/workspaces/",
        }
    )


urlpatterns = [
    path("", root),
    path("admin/", admin.site.urls),
    path("_allauth/", include("allauth.headless.urls")),
    path("api/v1/", include("workspace_registry.public_urls")),
    path("t/<slug:tenant_slug>/_allauth/", include("allauth.headless.urls")),
    path("t/<slug:tenant_slug>/api/v1/", include("linesight.tenant_urls")),
]
