from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    """Base class for ORM models. Models are added in a later step
    (District, Block, GP, POP, Employee, PMVisit, PMPhoto —
    see docs/data-model.md)."""
