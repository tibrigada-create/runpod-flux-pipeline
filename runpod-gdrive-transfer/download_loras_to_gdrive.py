#!/usr/bin/env python3
import csv
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse

import requests
from huggingface_hub import HfApi, hf_hub_download
from huggingface_hub.errors import HfHubHTTPError, RepositoryNotFoundError


MIN_VALID_MODEL_BYTES = 1024 * 1024


@dataclass
class Config:
    csv_path: Path
    download_staging: Path
    archive_dir: Path
    lora_archive_name: str
    rclone_remote: str
    drive_lora_dir: str
    log_dir: Path


def env(name: str, default: str) -> str:
    return os.environ.get(name, default)


def load_config() -> Config:
    script_dir = Path(__file__).resolve().parent
    return Config(
        csv_path=Path(env("LORAS_CSV", str(script_dir / "loras.csv"))),
        download_staging=Path(env("DOWNLOAD_STAGING", "/workspace/_download_staging")),
        archive_dir=Path(env("ARCHIVE_DIR", "/workspace/_archives")),
        lora_archive_name=env("LORA_ARCHIVE_NAME", "flux_loras_bundle.tar"),
        rclone_remote=env("RCLONE_REMOTE", "gdrive"),
        drive_lora_dir=env("DRIVE_LORA_DIR", "RunPod_Backup/loras"),
        log_dir=Path(env("LOG_DIR", str(script_dir / "logs"))),
    )


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def human_size(num: int) -> str:
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if num < 1024:
            return f"{num:.1f} {unit}"
        num /= 1024
    return f"{num:.1f} PB"


def ensure_space(target_dir: Path, required_bytes: int) -> None:
    target_dir.mkdir(parents=True, exist_ok=True)
    free = shutil.disk_usage(target_dir).free
    if free < required_bytes:
        raise RuntimeError(
            f"Not enough free space at {target_dir}. Need about {human_size(required_bytes)}, "
            f"free {human_size(free)}."
        )


def parse_hf_repo_id(url: str) -> Optional[str]:
    parsed = urlparse(url)
    if parsed.netloc != "huggingface.co":
        return None
    parts = [p for p in parsed.path.split("/") if p]
    if len(parts) < 2:
        return None
    return f"{parts[0]}/{parts[1]}"


def find_hf_file(row: dict, report: list[str]) -> tuple[Optional[str], Optional[str]]:
    repo_id = parse_hf_repo_id(row["source_url"])
    if not repo_id:
        return None, "Could not parse Hugging Face repo_id"

    token = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN")
    api = HfApi(token=token)
    expected = row["expected_filename"]
    try:
        files = api.list_repo_files(repo_id=repo_id, repo_type="model")
    except (RepositoryNotFoundError, HfHubHTTPError) as exc:
        return None, f"Hugging Face repo unavailable or gated: {exc}"

    safetensors = [f for f in files if f.endswith((".safetensors", ".sft", ".pt"))]
    if expected in safetensors:
        return expected, None

    basename_matches = [f for f in safetensors if Path(f).name == expected]
    if basename_matches:
        return basename_matches[0], None

    report.append(f"- HF unresolved `{row['name']}`: expected `{expected}` not found in `{repo_id}`.")
    if safetensors:
        report.append("  Available model files:")
        for item in safetensors[:20]:
            report.append(f"  - `{item}`")
    return None, "Expected Hugging Face file not found"


def download_hf(row: dict, cfg: Config, report: list[str]) -> Optional[Path]:
    repo_id = parse_hf_repo_id(row["source_url"])
    file_in_repo, error = find_hf_file(row, report)
    if not repo_id or not file_in_repo:
        report.append(f"- SKIP `{row['name']}`: {error}")
        return None

    dest_name = Path(file_in_repo).name
    dest = cfg.download_staging / dest_name
    if dest.exists() and dest.stat().st_size >= MIN_VALID_MODEL_BYTES:
        report.append(f"- OK existing HF `{dest_name}` ({human_size(dest.stat().st_size)})")
        return dest

    token = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN")
    report.append(f"- Downloading HF `{repo_id}/{file_in_repo}`")
    try:
        downloaded = hf_hub_download(
            repo_id=repo_id,
            filename=file_in_repo,
            repo_type="model",
            token=token,
            local_dir=str(cfg.download_staging),
        )
    except Exception as exc:
        report.append(f"- FAIL HF `{row['name']}`: {exc}")
        return None

    path = Path(downloaded)
    final = cfg.download_staging / path.name
    if path != final and path.exists():
        shutil.copy2(path, final)
    if final.stat().st_size < MIN_VALID_MODEL_BYTES:
        report.append(f"- FAIL HF `{row['name']}`: downloaded file is too small: {final.stat().st_size} bytes")
        return None
    return final


def civitai_model_id(url: str) -> Optional[str]:
    m = re.search(r"civitai\.com/models/(\d+)", url)
    return m.group(1) if m else None


def request_json(url: str, headers: dict) -> dict:
    last_exc = None
    for attempt in range(1, 4):
        try:
            r = requests.get(url, headers=headers, timeout=60)
            if r.status_code == 200:
                return r.json()
            raise RuntimeError(f"HTTP {r.status_code}: {r.text[:300]}")
        except Exception as exc:
            last_exc = exc
            time.sleep(2 * attempt)
    raise RuntimeError(str(last_exc))


def choose_civitai_file(model: dict, expected: str) -> tuple[Optional[dict], str]:
    candidates = []
    for version in model.get("modelVersions") or []:
        for file_info in version.get("files") or []:
            name = file_info.get("name") or ""
            if name.endswith((".safetensors", ".sft", ".pt")):
                candidates.append(file_info)
                if name == expected or Path(name).name == expected:
                    return file_info, "exact"
    if candidates:
        return candidates[0], "fallback"
    return None, "none"


def stream_download(url: str, dest: Path, headers: dict, report: list[str]) -> bool:
    tmp = dest.with_suffix(dest.suffix + ".part")
    headers = dict(headers)
    headers.setdefault("User-Agent", "Mozilla/5.0 runpod-gdrive-transfer")

    with requests.get(url, headers=headers, stream=True, timeout=(30, 120), allow_redirects=True) as r:
        if r.status_code != 200:
            report.append(f"- FAIL download HTTP {r.status_code}: {url}")
            return False
        total = int(r.headers.get("content-length") or 0)
        downloaded = 0
        last_print = 0
        with tmp.open("wb") as f:
            for chunk in r.iter_content(chunk_size=1024 * 1024):
                if not chunk:
                    continue
                f.write(chunk)
                downloaded += len(chunk)
                now = time.time()
                if now - last_print > 2:
                    if total:
                        print(f"  {dest.name}: {human_size(downloaded)} / {human_size(total)}")
                    else:
                        print(f"  {dest.name}: {human_size(downloaded)}")
                    last_print = now

    if tmp.stat().st_size < MIN_VALID_MODEL_BYTES:
        report.append(f"- FAIL tiny file `{dest.name}`: {tmp.stat().st_size} bytes")
        tmp.unlink(missing_ok=True)
        return False
    tmp.replace(dest)
    return True


def download_civitai(row: dict, cfg: Config, report: list[str]) -> Optional[Path]:
    model_id = civitai_model_id(row["source_url"])
    if not model_id:
        report.append(f"- SKIP Civitai `{row['name']}`: could not parse model id")
        return None

    token = os.environ.get("CIVITAI_TOKEN")
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    else:
        report.append(f"- WARN Civitai token missing. If `{row['name']}` is gated, set CIVITAI_TOKEN.")

    try:
        model = request_json(f"https://civitai.com/api/v1/models/{model_id}", headers)
    except Exception as exc:
        report.append(f"- FAIL Civitai metadata `{row['name']}`: {exc}")
        return None

    file_info, match_type = choose_civitai_file(model, row["expected_filename"])
    if not file_info:
        report.append(f"- SKIP Civitai `{row['name']}`: no downloadable model file found")
        return None

    real_name = file_info.get("name") or row["expected_filename"]
    dest = cfg.download_staging / Path(real_name).name
    if dest.exists() and dest.stat().st_size >= MIN_VALID_MODEL_BYTES:
        report.append(f"- OK existing Civitai `{dest.name}` ({human_size(dest.stat().st_size)})")
        return dest

    download_url = file_info.get("downloadUrl")
    if not download_url:
        report.append(f"- FAIL Civitai `{row['name']}`: metadata has no downloadUrl")
        return None

    if match_type != "exact":
        report.append(
            f"- NOTE Civitai `{row['name']}` expected `{row['expected_filename']}`, "
            f"using real file `{dest.name}`."
        )

    ok = stream_download(download_url, dest, headers, report)
    return dest if ok else None


def download_github(row: dict, cfg: Config, report: list[str]) -> Optional[Path]:
    report.append(
        f"- UNRESOLVED GitHub `{row['name']}`: not downloading HTML pages blindly. "
        f"Find a release asset or direct raw `.safetensors` URL manually: {row['source_url']}"
    )
    return None


def create_tar(cfg: Config, files: list[Path], report: list[str]) -> Path:
    archive = cfg.archive_dir / cfg.lora_archive_name
    archive.unlink(missing_ok=True)
    cfg.archive_dir.mkdir(parents=True, exist_ok=True)
    total = sum(p.stat().st_size for p in files if p.exists())
    ensure_space(cfg.archive_dir, total)
    with tarfile.open(archive, "w") as tar:
        for file_path in files:
            tar.add(file_path, arcname=file_path.name)
    report.append(f"- Created tar `{archive}` ({human_size(archive.stat().st_size)})")
    return archive


def run_rclone_copy(src: Path, remote: str, report: list[str]) -> None:
    report.append(f"- Uploading `{src.name}` to `{remote}`")
    subprocess.run(["rclone", "copy", str(src), remote, "--progress"], check=True)


def main() -> int:
    cfg = load_config()
    cfg.download_staging.mkdir(parents=True, exist_ok=True)
    cfg.archive_dir.mkdir(parents=True, exist_ok=True)
    cfg.log_dir.mkdir(parents=True, exist_ok=True)

    if not cfg.csv_path.exists():
        print(f"[ERROR] CSV not found: {cfg.csv_path}", file=sys.stderr)
        return 1

    report = [
        "# LoRA Download Report",
        "",
        f"Created: {time.strftime('%Y-%m-%d %H:%M:%S')}",
        "",
    ]
    downloaded: list[Path] = []

    with cfg.csv_path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            source_type = (row.get("source_type") or "").strip().lower()
            name = row.get("name") or row.get("expected_filename") or "unknown"
            report.append(f"## {row.get('id', '?')}. {name}")

            path = None
            if source_type == "huggingface":
                path = download_hf(row, cfg, report)
            elif source_type == "civitai":
                path = download_civitai(row, cfg, report)
            elif source_type == "github":
                path = download_github(row, cfg, report)
            else:
                report.append(f"- SKIP unsupported source_type `{source_type}`")

            if path and path.exists() and path.stat().st_size >= MIN_VALID_MODEL_BYTES:
                digest = sha256_file(path)
                report.append(f"- OK `{path.name}` size `{human_size(path.stat().st_size)}` sha256 `{digest}`")
                downloaded.append(path)
            report.append("")

    report_path = cfg.archive_dir / "lora_download_report.md"
    manifest_path = cfg.archive_dir / "lora_manifest.txt"
    sha_path = cfg.archive_dir / "sha256sum.txt"

    manifest_lines = []
    sha_lines = []
    for path in downloaded:
        digest = sha256_file(path)
        manifest_lines.append(f"{path.name}\t{path.stat().st_size}\t{digest}")
        sha_lines.append(f"{digest}  {path.name}")

    manifest_path.write_text("\n".join(manifest_lines) + ("\n" if manifest_lines else ""), encoding="utf-8")
    sha_path.write_text("\n".join(sha_lines) + ("\n" if sha_lines else ""), encoding="utf-8")

    if downloaded:
        archive = create_tar(cfg, downloaded, report)
    else:
        report.append("- No LoRA files were downloaded. Tar archive was not created.")
        archive = None

    report_path.write_text("\n".join(report), encoding="utf-8")
    print(report_path.read_text(encoding="utf-8"))

    remote = f"{cfg.rclone_remote}:{cfg.drive_lora_dir}/"
    subprocess.run(["rclone", "mkdir", remote], check=True)
    if archive:
        run_rclone_copy(archive, remote, report)
    run_rclone_copy(report_path, remote, report)
    run_rclone_copy(manifest_path, remote, report)
    run_rclone_copy(sha_path, remote, report)

    report_path.write_text("\n".join(report), encoding="utf-8")
    subprocess.run(["rclone", "copy", str(report_path), remote, "--progress"], check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
