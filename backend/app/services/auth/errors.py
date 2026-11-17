class AuthenticationError(Exception):
    """Raised by an AuthStrategy when login should be rejected.

    status_code is the HTTP status the endpoint should respond with
    (401 for wrong credentials, 403 for a recognized but blocked account).
    """

    def __init__(self, message: str, status_code: int = 401):
        self.message = message
        self.status_code = status_code
        super().__init__(message)
