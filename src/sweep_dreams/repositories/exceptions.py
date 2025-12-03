"""Domain-specific exceptions for repository failures."""


class ScheduleRepositoryError(Exception):
    """Base exception for schedule repository errors."""

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


class SubscriptionRepositoryError(Exception):
    """Base exception for subscription repository errors."""

    pass


class SubscriptionNotFoundError(SubscriptionRepositoryError):
    """Raised when a subscription cannot be found."""

    pass
