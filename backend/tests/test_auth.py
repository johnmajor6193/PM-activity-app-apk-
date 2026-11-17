from app.models.employee import Employee


def _create_employee(db_session, **overrides):
    defaults = dict(
        employee_code="TESTENG01",
        name="Test Engineer",
        mobile_number="9876543210",
        assigned_district_name="Chennai",
        is_active=True,
    )
    defaults.update(overrides)
    employee = Employee(**defaults)
    db_session.add(employee)
    db_session.commit()
    return employee


def test_login_succeeds_with_valid_employee_id_and_mobile_number(client, db_session):
    _create_employee(db_session, employee_code="TESTENG01", mobile_number="9876543210")

    response = client.post(
        "/api/v1/auth/login",
        json={"employee_id": "TESTENG01", "mobile_number": "9876543210"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["token_type"] == "bearer"
    assert body["access_token"]
    assert body["employee"] == {
        "employee_id": "TESTENG01",
        "name": "Test Engineer",
        "assigned_district": "Chennai",
    }


def test_login_fails_with_wrong_mobile_number(client, db_session):
    _create_employee(db_session, employee_code="TESTENG02", mobile_number="9876543211")

    response = client.post(
        "/api/v1/auth/login",
        json={"employee_id": "TESTENG02", "mobile_number": "9999999999"},
    )

    assert response.status_code == 401
    assert response.json()["detail"] == "Invalid Employee ID or mobile number."


def test_login_fails_for_unknown_employee_id(client):
    response = client.post(
        "/api/v1/auth/login",
        json={"employee_id": "DOES-NOT-EXIST", "mobile_number": "9876543210"},
    )

    assert response.status_code == 401
    assert response.json()["detail"] == "Invalid Employee ID or mobile number."


def test_login_fails_for_inactive_employee(client, db_session):
    _create_employee(
        db_session,
        employee_code="TESTENG03",
        mobile_number="9876543212",
        is_active=False,
    )

    response = client.post(
        "/api/v1/auth/login",
        json={"employee_id": "TESTENG03", "mobile_number": "9876543212"},
    )

    assert response.status_code == 403
    assert "inactive" in response.json()["detail"].lower()


def test_login_rejects_invalid_mobile_number_format(client):
    response = client.post(
        "/api/v1/auth/login",
        json={"employee_id": "TESTENG01", "mobile_number": "12345"},
    )

    assert response.status_code == 422


def test_login_rejects_blank_employee_id(client):
    response = client.post(
        "/api/v1/auth/login",
        json={"employee_id": "   ", "mobile_number": "9876543210"},
    )

    assert response.status_code == 422


def test_dev_seed_employee_can_log_in(client):
    """Sanity check for the auto-seeded demo account (see
    app/db/seed_dev_data.py) that the mobile app's dev build is expected
    to use."""
    response = client.post(
        "/api/v1/auth/login",
        json={"employee_id": "ENG001", "mobile_number": "9876543210"},
    )

    assert response.status_code == 200
    assert response.json()["employee"]["assigned_district"] == "Chennai"
