from pydantic import BaseModel, ConfigDict


class DistrictOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str


class BlockOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    district_id: int


class GpOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    block_id: int


class PopSummary(BaseModel):
    """A POP as listed under a GP. No GPS/geofence fields — see
    app/models/pop.py for why."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    pop_code: str
    name: str | None = None
    is_active: bool
    gp_id: int


class PopDetail(PopSummary):
    """A single POP's basic details, with its full location hierarchy
    resolved for display. No GPS/geofence fields — see
    app/models/pop.py for why."""

    gp_name: str
    block_name: str
    district_name: str
