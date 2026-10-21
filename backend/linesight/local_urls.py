from django.http import JsonResponse
from django.contrib import admin
from django.urls import include, path


def health(request):
    return JsonResponse({"name": "LineSight", "api": "v1", "status": "ready"})


urlpatterns = [path("", health), path("admin/", admin.site.urls), path("api/v1/", include("collaboration.urls"))]
