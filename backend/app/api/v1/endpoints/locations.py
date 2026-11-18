from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.api.deps import get_current_employee
from app.db.deps import get_db
from app.models.block import Block
from app.models.district import District
from app.models.grama_panchayat import GramaPanchayat
from app.models.pop import Pop
from app.schemas.location import BlockOut, DistrictOut, GpOut, PopDetail, PopSummary

# Every route below requires a logged-in employee - these are the
# District -> Block -> GP -> POP lookups the mobile app's POP Selection
# screen depends on, only reachable after Employee Login.
router = APIRouter(
    prefix="/locations", tags=["locations"], dependencies=[Depends(get_current_employee)]
)


def _get_or_404(db: Session, model: type, obj_id: int, label: str):
    obj = db.get(model, obj_id)
    if obj is None:
        raise HTTPException(status_code=404, detail=f"{label} not found.")
    return obj


@router.get("/districts", response_model=list[DistrictOut])
def list_districts(db: Session = Depends(get_db)) -> list[District]:
    return db.query(District).order_by(District.name).all()


@router.get("/districts/{district_id}/blocks", response_model=list[BlockOut])
def list_blocks(district_id: int, db: Session = Depends(get_db)) -> list[Block]:
    _get_or_404(db, District, district_id, "District")
    return (
        db.query(Block)
        .filter(Block.district_id == district_id)
        .order_by(Block.name)
        .all()
    )


@router.get("/blocks/{block_id}/gps", response_model=list[GpOut])
def list_gps(block_id: int, db: Session = Depends(get_db)) -> list[GramaPanchayat]:
    _get_or_404(db, Block, block_id, "Block")
    return (
        db.query(GramaPanchayat)
        .filter(GramaPanchayat.block_id == block_id)
        .order_by(GramaPanchayat.name)
        .all()
    )


@router.get("/gps/{gp_id}/pops", response_model=list[PopSummary])
def list_pops(
    gp_id: int, active_only: bool = True, db: Session = Depends(get_db)
) -> list[Pop]:
    _get_or_404(db, GramaPanchayat, gp_id, "GP")
    query = db.query(Pop).filter(Pop.gp_id == gp_id)
    if active_only:
        query = query.filter(Pop.is_active.is_(True))
    return query.order_by(Pop.pop_code).all()


@router.get("/pops/{pop_id}", response_model=PopDetail)
def get_pop(pop_id: int, db: Session = Depends(get_db)) -> PopDetail:
    pop = _get_or_404(db, Pop, pop_id, "POP")
    gp = pop.gp
    block = gp.block
    district = block.district
    return PopDetail(
        id=pop.id,
        pop_code=pop.pop_code,
        name=pop.name,
        is_active=pop.is_active,
        gp_id=pop.gp_id,
        gp_name=gp.name,
        block_name=block.name,
        district_name=district.name,
    )
