"""
One-time helper to generate a Google Drive OAuth2 Refresh Token for CI/CD.
Reads GDRIVE_CLIENT_ID and GDRIVE_CLIENT_SECRET from env/google_drive.local.json,
opens the browser for Google login, and prints the refresh token to copy into
GitHub Secrets as GDRIVE_REFRESH_TOKEN.
"""

import http.server
import json
import os
import urllib.parse
import urllib.request
import webbrowser


def main() -> None:
    cfg_path = os.path.join("env", "google_drive.local.json")
    with open(cfg_path, "r", encoding="utf-8") as f:
        cfg = json.load(f)

    client_id = cfg["GDRIVE_CLIENT_ID"].strip()
    client_secret = cfg["GDRIVE_CLIENT_SECRET"].strip()
    redirect_uri = "http://127.0.0.1:8765/callback"
    scope = "https://www.googleapis.com/auth/drive.file"

    auth_url = (
        "https://accounts.google.com/o/oauth2/v2/auth?"
        + urllib.parse.urlencode({
            "client_id": client_id,
            "redirect_uri": redirect_uri,
            "response_type": "code",
            "scope": scope,
            "access_type": "offline",
            "prompt": "consent",
        })
    )

    code_holder = {"code": None}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)
            qs = urllib.parse.parse_qs(parsed.query)
            if "code" in qs:
                code_holder["code"] = qs["code"][0]
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.end_headers()
                self.wfile.write(
                    "<h2>Success! Return to PowerShell to copy your Refresh Token.</h2>".encode("utf-8")
                )
            else:
                self.send_response(400)
                self.end_headers()

        def log_message(self, format, *args):
            pass

    server = http.server.HTTPServer(("127.0.0.1", 8765), Handler)
    print("Opening browser for Google Drive authorization...")
    webbrowser.open(auth_url)

    while code_holder["code"] is None:
        server.handle_request()
    server.server_close()

    data = urllib.parse.urlencode({
        "code": code_holder["code"],
        "client_id": client_id,
        "client_secret": client_secret,
        "redirect_uri": redirect_uri,
        "grant_type": "authorization_code",
    }).encode("utf-8")
    req = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=data,
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        tokens = json.loads(resp.read().decode("utf-8"))

    print("\n=== COPY THIS INTO GITHUB SECRET: GDRIVE_REFRESH_TOKEN ===")
    print(tokens.get("refresh_token", "ERROR: no refresh_token returned"))
    print("==========================================================\n")


if __name__ == "__main__":
    main()
