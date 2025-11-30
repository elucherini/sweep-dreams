import pytest

from tests.factories import make_schedule


@pytest.fixture
def schedule_factory():
    return make_schedule
