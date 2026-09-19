"""Create the admin user if it does not exist. Managed by the dashboard Helm chart.

The password is read from a mounted Secret file rather than passed to
`superset fab create-admin --password ...`, which would put it in the
process's argv.
"""

import os
import sys
from pathlib import Path

from superset.app import create_app

app = create_app()

with app.app_context():
    from superset.extensions import security_manager as sm

    username = os.environ["ADMIN_USERNAME"]
    password = Path(os.environ["ADMIN_PASSWORD_FILE"]).read_text().rstrip("\r\n")
    if not password:
        sys.exit("admin password file is empty")

    user = sm.find_user(username=username)
    if user is None:
        role = sm.find_role("Admin")
        if role is None:
            sys.exit("the Admin role does not exist; `superset init` must run first")
        created = sm.add_user(
            username,
            os.environ.get("ADMIN_FIRST_NAME", "Superset"),
            os.environ.get("ADMIN_LAST_NAME", "Admin"),
            os.environ["ADMIN_EMAIL"],
            role,
            password=password,
        )
        if not created:
            sys.exit(f"could not create admin user {username!r}")
        print(f"created admin user {username!r}")
    elif os.environ.get("ADMIN_RESET_PASSWORD") == "true":
        sm.reset_password(user.id, password)
        print(f"reset the password of admin user {username!r}")
    else:
        print(f"admin user {username!r} exists; left unchanged")
