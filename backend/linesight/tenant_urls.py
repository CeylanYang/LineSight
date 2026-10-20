from django.urls import include, path

from inspection.api import urlpatterns as inspection_urls
from production.api import urlpatterns as production_urls
from quality.api import urlpatterns as quality_urls
from workspace_registry.api import urlpatterns as workspace_urls


urlpatterns = (
    list(workspace_urls)
    + list(inspection_urls)
    + list(production_urls)
    + list(quality_urls)
)
