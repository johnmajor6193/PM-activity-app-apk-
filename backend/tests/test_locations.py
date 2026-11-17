import pytest


@pytest.fixture()
def hierarchy_ids(client):
    """Walks the seeded dev hierarchy (see app/db/seed_dev_data.py) down
    to Chennai → Sholinganallur → Semmancheri GP, and its two POPs (one
    active, one inactive)."""
    districts = client.get("/api/v1/locations/districts").json()
    chennai = next(d for d in districts if d["name"] == "Chennai")

    blocks = client.get(f"/api/v1/locations/districts/{chennai['id']}/blocks").json()
    sholinganallur = next(b for b in blocks if b["name"] == "Sholinganallur")

    gps = client.get(f"/api/v1/locations/blocks/{sholinganallur['id']}/gps").json()
    semmancheri = next(g for g in gps if g["name"] == "Semmancheri GP")

    pops = client.get(
        f"/api/v1/locations/gps/{semmancheri['id']}/pops?active_only=false"
    ).json()
    active_pop = next(p for p in pops if p["pop_code"] == "POP-CHN-001")
    inactive_pop = next(p for p in pops if p["pop_code"] == "POP-CHN-002")

    return {
        "district_id": chennai["id"],
        "block_id": sholinganallur["id"],
        "gp_id": semmancheri["id"],
        "active_pop_id": active_pop["id"],
        "inactive_pop_id": inactive_pop["id"],
    }


def test_list_districts_returns_seeded_hierarchy(client):
    response = client.get("/api/v1/locations/districts")

    assert response.status_code == 200
    names = {d["name"] for d in response.json()}
    assert {"Chennai", "Madurai"}.issubset(names)


def test_list_blocks_for_district(client, hierarchy_ids):
    response = client.get(
        f"/api/v1/locations/districts/{hierarchy_ids['district_id']}/blocks"
    )

    assert response.status_code == 200
    names = {b["name"] for b in response.json()}
    assert {"Sholinganallur", "Tambaram"}.issubset(names)


def test_list_blocks_for_unknown_district_returns_404(client):
    response = client.get("/api/v1/locations/districts/999999/blocks")

    assert response.status_code == 404


def test_list_gps_for_block(client, hierarchy_ids):
    response = client.get(f"/api/v1/locations/blocks/{hierarchy_ids['block_id']}/gps")

    assert response.status_code == 200
    names = {g["name"] for g in response.json()}
    assert {"Semmancheri GP", "Kazhipattur GP"}.issubset(names)


def test_list_gps_for_unknown_block_returns_404(client):
    response = client.get("/api/v1/locations/blocks/999999/gps")

    assert response.status_code == 404


def test_list_pops_defaults_to_active_only(client, hierarchy_ids):
    response = client.get(f"/api/v1/locations/gps/{hierarchy_ids['gp_id']}/pops")

    assert response.status_code == 200
    codes = {p["pop_code"] for p in response.json()}
    assert "POP-CHN-001" in codes
    assert "POP-CHN-002" not in codes


def test_list_pops_with_active_only_false_includes_inactive(client, hierarchy_ids):
    response = client.get(
        f"/api/v1/locations/gps/{hierarchy_ids['gp_id']}/pops?active_only=false"
    )

    assert response.status_code == 200
    codes = {p["pop_code"] for p in response.json()}
    assert {"POP-CHN-001", "POP-CHN-002"}.issubset(codes)


def test_list_pops_for_unknown_gp_returns_404(client):
    response = client.get("/api/v1/locations/gps/999999/pops")

    assert response.status_code == 404


def test_pop_summary_has_no_gps_fields(client, hierarchy_ids):
    response = client.get(f"/api/v1/locations/gps/{hierarchy_ids['gp_id']}/pops")

    pop = response.json()[0]
    assert "latitude" not in pop
    assert "longitude" not in pop
    assert "geofence_radius_m" not in pop


def test_get_pop_detail_includes_full_hierarchy_names(client, hierarchy_ids):
    response = client.get(f"/api/v1/locations/pops/{hierarchy_ids['active_pop_id']}")

    assert response.status_code == 200
    body = response.json()
    assert body["pop_code"] == "POP-CHN-001"
    assert body["is_active"] is True
    assert body["gp_name"] == "Semmancheri GP"
    assert body["block_name"] == "Sholinganallur"
    assert body["district_name"] == "Chennai"
    assert "latitude" not in body
    assert "longitude" not in body


def test_get_pop_detail_for_inactive_pop_reports_status(client, hierarchy_ids):
    response = client.get(f"/api/v1/locations/pops/{hierarchy_ids['inactive_pop_id']}")

    assert response.status_code == 200
    assert response.json()["is_active"] is False


def test_get_pop_detail_for_unknown_id_returns_404(client):
    response = client.get("/api/v1/locations/pops/999999")

    assert response.status_code == 404
