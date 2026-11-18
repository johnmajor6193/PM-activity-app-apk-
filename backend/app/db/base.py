from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    """Base class for ORM models. District, Block, GramaPanchayat, Pop,
    and Employee are implemented (see app/models/). PMVisit and PMPhoto
    are intentionally not modeled here — the mobile app stores them
    on-device only and the backend stays a stateless Google Drive relay
    (see docs/data-model.md, "PM Visit & PM Photo — Local (On-Device)
    Implementation")."""
