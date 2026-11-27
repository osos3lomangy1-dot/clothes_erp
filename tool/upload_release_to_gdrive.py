"""
Uploads the latest Windows release artifacts to a Google Drive folder
and deletes any previous release files in that folder so new customers
always download the latest version.

Uses only Python standard library (zero external dependencies).
Required environment variables:
  - GDRIVE_CLIENT_ID
  - GDRIVE_CLIENT_SECRET
  - GDRIVE_REFRESH_TOKEN
  - GDRIVE_FOLDER_ID
"""

import glob
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


def get_access_token(client_id: str, client_secret: str, refresh_token: str) -> str:
    data = urllib.parse.urlencode({
        "client_id": client_id,
        "client_secret": client_secret,
        "refresh_token": refresh_token,
        "grant_type": "refresh_token",
    }).encode("utf-8")
    req = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=data,
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
        return payload["access_token"]


def list_folder_files(token: str, folder_id: str) -> list[dict]:
    q = urllib.parse.quote(f"'{folder_id}' in parents and trashed = false")
    url = f"https://www.googleapis.com/drive/v3/files?q={q}&fields=files(id,name)"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8")).get("files", [])


def delete_file(token: str, file_id: str, name: str) -> None:
    url = f"https://www.googleapis.com/drive/v3/files/{file_id}"
    req = urllib.request.Request(
        url,
        headers={"Authorization": f"Bearer {token}"},
        method="DELETE",
    )
    with urllib.request.urlopen(req, timeout=30):
        print(f"Deleted old file from Drive: {name} ({file_id})")


def upload_file_resumable(token: str, folder_id: str, file_path: str) -> None:
    file_name = os.path.basename(file_path)
    file_size = os.path.getsize(file_path)
    meta = json.dumps({"name": file_name, "parents": [folder_id]}).encode("utf-8")

    init_req = urllib.request.Request(
        "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable",
        data=meta,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json; charset=UTF-8",
            "X-Upload-Content-Type": "application/octet-stream",
            "X-Upload-Content-Length": str(file_size),
        },
        method="POST",
    )
    with urllib.request.urlopen(init_req, timeout=30) as resp:
        upload_url = resp.headers["Location"]

    with open(file_path, "rb") as f:
        data = f.read()

    put_req = urllib.request.Request(
        upload_url,
        data=data,
        headers={
            "Content-Type": "application/octet-stream",
            "Content-Length": str(file_size),
        },
        method="PUT",
    )
    with urllib.request.urlopen(put_req, timeout=300) as resp:
        res = json.loads(resp.read().decode("utf-8"))
        print(f"Uploaded to Drive: {file_name} -> id={res.get('id')}")


def main() -> int:
    client_id = os.environ.get("GDRIVE_CLIENT_ID", "").strip()
    client_secret = os.environ.get("GDRIVE_CLIENT_SECRET", "").strip()
    refresh_token = os.environ.get("GDRIVE_REFRESH_TOKEN", "").strip()
    folder_id = os.environ.get("GDRIVE_FOLDER_ID", "").strip()

    if not all([client_id, client_secret, refresh_token, folder_id]):
        print("Missing Google Drive secrets; skipping Drive upload.")
        return 0

    files_to_upload: list[str] = []
    for pattern in sys.argv[1:]:
        files_to_upload.extend(sorted(glob.glob(pattern)))

    files_to_upload = [f for f in files_to_upload if os.path.isfile(f)]
    if not files_to_upload:
        print("No release files matched to upload.")
        return 0

    token = get_access_token(client_id, client_secret, refresh_token)

    # 1. Delete old files in the target Drive folder
    existing = list_folder_files(token, folder_id)
    for item in existing:
        delete_file(token, item["id"], item["name"])

    # 2. Upload new release files
    for path in files_to_upload:
        upload_file_resumable(token, folder_id, path)

    print("Google Drive release sync completed successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
