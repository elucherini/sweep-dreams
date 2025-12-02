"""FastAPI application factory."""

from fastapi import FastAPI, Query, Depends
from fastapi.middleware.cors import CORSMiddleware

from sweep_dreams.config.settings import get_settings
from sweep_dreams.api import routes
from sweep_dreams.api.models import CheckLocationResponse


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
    # Tests can override this dependency
    from sweep_dreams.api.dependencies import repository_dependency

    @app.get("/check-location", response_model=CheckLocationResponse)
    def check_location_route(
        latitude: float = Query(..., ge=-90, le=90),
        longitude: float = Query(..., ge=-180, le=180),
        repository = Depends(repository_dependency),
    ):
        return routes.check_location(latitude, longitude, repository)

    @app.get("/api/check-location", response_model=CheckLocationResponse)
    def check_location_api_route(
        latitude: float = Query(..., ge=-90, le=90),
        longitude: float = Query(..., ge=-180, le=180),
        repository = Depends(repository_dependency),
    ):
        return routes.check_location(latitude, longitude, repository)

    return app


# For uvicorn: uvicorn sweep_dreams.api.app:app
app = create_app()
