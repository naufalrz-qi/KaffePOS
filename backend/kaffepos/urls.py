from django.urls import include, path

from api.api import api

urlpatterns = [
    path("api/v1/", api.urls),
    path("", include("dashboard.urls")),
]
