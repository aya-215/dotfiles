#!/usr/bin/env python3
"""PR DiffView Server - ブラウザのPRページからNeovim diffview.nvimを開くHTTPサーバー"""

import logging
import os
import subprocess
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

logging.basicConfig(level=logging.WARNING)
logger = logging.getLogger(__name__)

app = FastAPI(title="PR DiffView Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

SCRIPT_DIR = Path(__file__).parent
OPEN_DIFFVIEW_SH = SCRIPT_DIR / "open-diffview.sh"


class OpenDiffviewRequest(BaseModel):
    host: str           # "github" or "gitbucket"
    owner: str
    repo: str
    pr_number: int
    head_ref: str | None = None


def resolve_repo_path(host: str, owner: str, repo: str) -> Path:
    """リポジトリのローカルパスを解決する"""
    home = Path.home()
    if host == "github":
        path = home / "src" / "github.com" / owner / repo
    elif host == "gitbucket":
        path = home / "src" / "192.168.208.80" / owner / repo
    else:
        raise ValueError(f"不明なホスト: {host}")

    if not path.exists():
        raise FileNotFoundError(f"リポジトリが見つかりません: {path}")

    return path


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/open-diffview")
async def open_diffview(req: OpenDiffviewRequest):
    try:
        repo_path = resolve_repo_path(req.host, req.owner, req.repo)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))

    cmd = [
        "bash",
        str(OPEN_DIFFVIEW_SH),
        str(repo_path),
        req.host,
        str(req.pr_number),
        req.head_ref or "",
    ]

    logger.info("Running: %s", " ".join(cmd))

    try:
        subprocess.Popen(
            cmd,
            stdout=open(Path.home() / ".local/log/pr-diffview.log", "a"),
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    except Exception as e:
        logger.error("Popen failed: %s", e)
        raise HTTPException(status_code=500, detail=f"スクリプト起動失敗: {e}")

    return {
        "status": "ok",
        "message": f"DiffViewを起動しました: {req.owner}/{req.repo}#{req.pr_number}",
        "repo_path": str(repo_path),
    }
