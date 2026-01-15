#!/usr/bin/env python3
"""
Claude Code会話をnbノートブックに同期するスクリプト

Claude Codeのセッションファイル(JSONL)を監視し、
会話内容をMarkdown形式で~/.nb/claude/に保存します。
"""

import json
import os
import sys
from pathlib import Path
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Optional, Set
import re


# 設定
CLAUDE_DIR = Path.home() / ".claude"
PROJECTS_DIR = CLAUDE_DIR / "projects"
STATE_FILE = CLAUDE_DIR / "nb-sync-state.json"
NB_CLAUDE_DIR = Path.home() / ".nb" / "claude"
MAX_FILE_AGE_DAYS = 7  # 何日前までのファイルを対象にするか
JST = timezone(timedelta(hours=9))  # 日本標準時


class SyncState:
    """同期状態を管理するクラス"""

    def __init__(self, state_file: Path):
        self.state_file = state_file
        self.state = self._load_state()

    def _load_state(self) -> Dict:
        """状態ファイルを読み込む"""
        if self.state_file.exists():
            try:
                with open(self.state_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except (json.JSONDecodeError, IOError) as e:
                print(f"Warning: Failed to load state file: {e}", file=sys.stderr)
                return {"version": "1.0", "sessions": {}}
        return {"version": "1.0", "sessions": {}}

    def save_state(self):
        """状態ファイルを保存する"""
        try:
            self.state_file.parent.mkdir(parents=True, exist_ok=True)
            with open(self.state_file, 'w', encoding='utf-8') as f:
                json.dump(self.state, f, indent=2, ensure_ascii=False)
        except IOError as e:
            print(f"Error: Failed to save state file: {e}", file=sys.stderr)

    def get_last_line(self, session_file: str) -> int:
        """指定されたセッションファイルの最終同期行番号を取得"""
        return self.state.get("sessions", {}).get(session_file, {}).get("last_line", 0)

    def update_session(self, session_file: str, last_line: int):
        """セッション情報を更新"""
        if "sessions" not in self.state:
            self.state["sessions"] = {}
        self.state["sessions"][session_file] = {
            "last_line": last_line,
            "last_sync": datetime.now().isoformat()
        }


def should_exclude_message(content: str, message_type: str) -> bool:
    """メッセージを除外すべきかどうか判定"""
    if not content:
        return True

    # 除外パターン
    exclude_patterns = [
        r'<system-reminder>',
        r'<local-command',
        r'<command-name>',
        r'<task-notification>',
    ]

    for pattern in exclude_patterns:
        if re.search(pattern, content):
            return True

    # userメッセージで"Warmup"のみの場合は除外
    if message_type == "user" and content.strip() == "Warmup":
        return True

    return False


def extract_text_from_content(content) -> str:
    """contentフィールドからテキストを抽出"""
    if isinstance(content, str):
        return content
    elif isinstance(content, list):
        # assistantメッセージの場合、type: text のものだけを抽出
        texts = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                texts.append(item.get("text", ""))
        return "\n".join(texts)
    return ""


def get_project_name_from_session(session_file: Path) -> str:
    """セッションファイルからプロジェクト名を取得（cwdを使用）"""
    try:
        with open(session_file, 'r', encoding='utf-8') as f:
            for line in f:
                try:
                    data = json.loads(line.strip())
                    if 'cwd' in data:
                        cwd = data['cwd']
                        project = Path(cwd).name
                        # ドットで始まる場合は除去
                        if project.startswith('.'):
                            project = project[1:]
                        return project if project else 'unknown'
                except json.JSONDecodeError:
                    continue
    except IOError:
        pass
    return 'unknown'


def process_session_file(session_file: Path, state: SyncState) -> List[Dict]:
    """セッションファイルを処理して新規メッセージを抽出"""
    session_path_str = str(session_file)
    last_line = state.get_last_line(session_path_str)

    # セッション開始時にプロジェクト名を1回だけ取得
    project_name = get_project_name_from_session(session_file)

    messages = []
    current_line = 0

    try:
        with open(session_file, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                if line_num <= last_line:
                    continue

                current_line = line_num

                try:
                    data = json.loads(line.strip())
                except json.JSONDecodeError:
                    continue

                msg_type = data.get("type")
                if msg_type not in ["user", "assistant"]:
                    continue

                message = data.get("message", {})
                content_raw = message.get("content", "")
                content = extract_text_from_content(content_raw)

                if should_exclude_message(content, msg_type):
                    continue

                timestamp_str = data.get("timestamp", "")
                try:
                    timestamp = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
                except (ValueError, AttributeError):
                    timestamp = datetime.now()

                messages.append({
                    "type": msg_type,
                    "content": content,
                    "timestamp": timestamp,
                    "project": project_name
                })

        # 最終行を更新
        if current_line > last_line:
            state.update_session(session_path_str, current_line)

    except IOError as e:
        print(f"Error reading {session_file}: {e}", file=sys.stderr)

    return messages


def format_messages_by_date(messages: List[Dict]) -> Dict[str, List[Dict]]:
    """メッセージを日付ごとにグループ化"""
    by_date = {}
    for msg in messages:
        date_str = msg["timestamp"].strftime("%Y-%m-%d")
        if date_str not in by_date:
            by_date[date_str] = []
        by_date[date_str].append(msg)
    return by_date


def format_message_as_markdown(msg: Dict) -> str:
    """メッセージをMarkdown形式に変換"""
    role = "**User:**" if msg["type"] == "user" else "**Claude:**"
    content = msg["content"].strip()
    return f"{role}\n{content}\n"


def write_to_nb(date_str: str, messages: List[Dict]):
    """メッセージをnbファイルに書き込む"""
    nb_file = NB_CLAUDE_DIR / f"{date_str}.md"

    # ファイルが存在しない場合はヘッダーを作成
    if not nb_file.exists():
        NB_CLAUDE_DIR.mkdir(parents=True, exist_ok=True)
        date_obj = datetime.strptime(date_str, "%Y-%m-%d")
        header = f"# Claude Code Conversations - {date_obj.strftime('%Y年%m月%d日')}\n\n"
        with open(nb_file, 'w', encoding='utf-8') as f:
            f.write(header)

    # プロジェクトごとにグループ化
    by_project = {}
    for msg in messages:
        project = msg["project"]
        if project not in by_project:
            by_project[project] = []
        by_project[project].append(msg)

    # 追記
    with open(nb_file, 'a', encoding='utf-8') as f:
        for project, proj_messages in by_project.items():
            # 会話のまとまりごとに出力
            f.write(f"## {project}\n")

            # タイムスタンプを取得（最初のメッセージ）- JSTに変換
            if proj_messages:
                time_str = proj_messages[0]["timestamp"].astimezone(JST).strftime("%H:%M")
                f.write(f"### {time_str}\n\n")

            for msg in proj_messages:
                f.write(format_message_as_markdown(msg))
                f.write("\n")

            f.write("---\n\n")


def find_recent_session_files() -> List[Path]:
    """最近更新されたセッションファイルを検索"""
    if not PROJECTS_DIR.exists():
        return []

    session_files = []
    cutoff_time = datetime.now().timestamp() - (MAX_FILE_AGE_DAYS * 24 * 3600)

    for project_dir in PROJECTS_DIR.iterdir():
        if not project_dir.is_dir():
            continue

        for jsonl_file in project_dir.glob("*.jsonl"):
            # ファイルの最終更新時刻をチェック
            if jsonl_file.stat().st_mtime > cutoff_time:
                session_files.append(jsonl_file)

    return session_files


def main():
    """メイン処理"""
    state = SyncState(STATE_FILE)

    # 最近のセッションファイルを検索
    session_files = find_recent_session_files()

    if not session_files:
        print("No recent session files found.")
        return

    # 全メッセージを収集
    all_messages = []
    for session_file in session_files:
        messages = process_session_file(session_file, state)
        all_messages.extend(messages)

    if not all_messages:
        print("No new messages to sync.")
        state.save_state()
        return

    # 日付ごとにグループ化して書き込み
    messages_by_date = format_messages_by_date(all_messages)

    for date_str, messages in sorted(messages_by_date.items()):
        write_to_nb(date_str, messages)
        print(f"Synced {len(messages)} messages to {date_str}.md")

    # 状態を保存
    state.save_state()
    print(f"Sync completed. Total: {len(all_messages)} messages")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
