"""FastAPI application factory."""

from fastapi import FastAPI, Query, Depends, Response
from fastapi.middleware.cors import CORSMiddleware

from sweep_dreams.config.settings import get_settings
from sweep_dreams.api import routes
from sweep_dreams.api.models import (
    CheckLocationResponse,
    SubscribeRequest,
    SubscriptionStatus,
)
from sweep_dreams.api.dependencies import (
    repository_dependency,
    subscription_service_dependency,
)


def create_app() -> FastAPI:
    """
    Factory function to create and configure the FastAPI application.

    Returns:
        Configured FastAPI instance
    """
    settings = get_settings()

    app = FastAPI(title="Sweep Dreams API")

    # Configure CORS
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors.allowed_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Health check endpoints
    @app.get("/health")
    @app.head("/health")
    def health_check():
        """Health check endpoint for monitoring and load balancers."""
        return {"status": "ok"}

    # Register route handlers using repository_dependency

    @app.get("/check-location", response_model=CheckLocationResponse)
    def check_location_route(
        latitude: float = Query(..., ge=-90, le=90),
        longitude: float = Query(..., ge=-180, le=180),
        repository=Depends(repository_dependency),
    ):
        return routes.check_location(latitude, longitude, repository)

    @app.get("/api/check-location", response_model=CheckLocationResponse)
    def check_location_api_route(
        latitude: float = Query(..., ge=-90, le=90),
        longitude: float = Query(..., ge=-180, le=180),
        repository=Depends(repository_dependency),
    ):
        return routes.check_location(latitude, longitude, repository)

    @app.post("/subscriptions", response_model=SubscriptionStatus)
    def subscribe_route(
        request: SubscribeRequest,
        service=Depends(subscription_service_dependency),
    ):
        return routes.subscribe_to_schedule(request, service)

    @app.get("/subscriptions/{device_token}", response_model=SubscriptionStatus)
    def subscription_status_route(
        device_token: str, service=Depends(subscription_service_dependency)
    ):
        return routes.get_subscription_status(device_token, service)

    @app.delete("/subscriptions/{device_token}", status_code=204)
    def delete_subscription_route(
        device_token: str, service=Depends(subscription_service_dependency)
    ):
        routes.delete_subscription(device_token, service)
        return Response(status_code=204)

    return app


# For uvicorn: uvicorn sweep_dreams.api.app:app
app = create_app()
