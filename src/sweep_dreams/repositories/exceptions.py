"""Domain-specific exceptions for repository failures."""


class ScheduleRepositoryError(Exception):
    """Base exception for repository errors."""
    pass


class ScheduleNotFoundError(ScheduleRepositoryError):
    """Raised when no schedules are found for a location."""
    pass


class RepositoryConnectionError(ScheduleRepositoryError):
    """Raised when the repository backend is unreachable."""
    pass


class RepositoryAuthenticationError(ScheduleRepositoryError):
    """Raised when repository authentication fails."""
    pass
