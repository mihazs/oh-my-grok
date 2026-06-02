#!/usr/bin/env python3
"""Boulder + todo continuation state (oh-my-openagent compatible)."""
from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

OMG_WORKSPACE_DIR = ".omg"
BOULDER_DIR = OMG_WORKSPACE_DIR
BOULDER_FILE = "boulder.json"
CONTINUATION_MARKER_DIR = f"{OMG_WORKSPACE_DIR}/run-continuation"
PROMETHEUS_PLANS_DIRS = (f"{OMG_WORKSPACE_DIR}/plans",)
TODO_MIRROR_DIR = f"{OMG_WORKSPACE_DIR}/todos"

TODO_CONTINUATION_PROMPT = """[TODO CONTINUATION]

Incomplete tasks remain in your todo list. Continue working on the next pending task.

- Proceed without asking for permission
- Mark each task complete when finished
- Do not stop until all tasks are done
- If you believe all work is already complete, critically re-examine each todo item and update the list accordingly."""

BOULDER_CONTINUATION_PROMPT = """[BOULDER CONTINUATION]

You have an active work plan with incomplete tasks. Continue working.

RULES:
- FIRST: Read the plan file NOW. If the last completed task is still unchecked, mark it `- [x]` IMMEDIATELY before anything else
- Proceed without asking for permission
- Use the notepad at .omg/notepads/{plan_name}/ to record learnings
- Do not stop until all tasks are complete
- If a task is blocked, edit the plan and change that checkbox from `- [ ]` to `- [~]` via a real file edit"""

BOULDER_COMPLETE_PROMPT = """<system-reminder>
BOULDER COMPLETE: plan "{plan_name}" is fully checked.

Total elapsed: {elapsed_human}

Per-task breakdown:
{task_breakdown}

Per your boulder_completion_response instructions, print the final ORCHESTRATION COMPLETE summary in your next turn. This nudge fires at most once.
</system-reminder>"""


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def parse_iso_ms(value: str | None) -> int | None:
    if not value:
        return None
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp() * 1000
    return int(parsed) if parsed else None


def format_duration_human(ms: int) -> str:
    if ms < 0:
        ms = 0
    seconds = ms // 1000
    if seconds < 60:
        return f"{seconds}s"
    minutes, seconds = divmod(seconds, 60)
    if minutes < 60:
        return f"{minutes}m {seconds}s"
    hours, minutes = divmod(minutes, 60)
    if hours < 24:
        return f"{hours}h {minutes}m"
    days, hours = divmod(hours, 24)
    return f"{days}d {hours}h"


def grok_home() -> Path:
    raw = os.environ.get("GROK_HOME") or ""
    if raw and raw.startswith("/") and "${" not in raw:
        return Path(raw)
    return Path.home() / ".grok"


def find_session_dir(session_id: str) -> Path | None:
    root = grok_home() / "sessions"
    if not root.is_dir() or not session_id:
        return None
    try:
        for workspace_dir in root.iterdir():
            if not workspace_dir.is_dir():
                continue
            candidate = workspace_dir / session_id
            if (candidate / "resources_state.json").is_file():
                return candidate
    except OSError:
        return None
    return None


def read_stdin_json(path: str) -> dict:
    if not path or not os.path.isfile(path):
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def pick(data: dict, *keys: str) -> str:
    for k in keys:
        v = data.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return ""


def should_allow_stop(data: dict) -> bool:
    stop_reason = pick(data, "stopReason", "stop_reason", "stop_reason_code")
    if stop_reason and stop_reason.lower() not in ("end_turn", "endturn", ""):
        return True
    if data.get("stop_hook_active") is True or data.get("stopHookActive") is True:
        return True
    bg = data.get("background_tasks") or data.get("backgroundTasks") or []
    if isinstance(bg, list):
        active = {"running", "pending", "in_progress", "in-progress", "active"}
        for task in bg:
            if isinstance(task, dict) and str(task.get("status", "")).lower() in active:
                return True
    return False


# --- continuation marker (.omg/run-continuation/<session>.json) ---


def marker_path(workspace: str, session_id: str) -> Path:
    return Path(workspace) / CONTINUATION_MARKER_DIR / f"{session_id}.json"


def is_continuation_stopped(workspace: str, session_id: str) -> bool:
    grok_flag = grok_home() / "state" / "stop-continuation" / session_id / "stopped"
    if grok_flag.is_file():
        return True
    mp = marker_path(workspace, session_id)
    if not mp.is_file():
        return False
    try:
        data = json.loads(mp.read_text(encoding="utf-8"))
        stop = (data.get("sources") or {}).get("stop") or {}
        return stop.get("state") == "stopped"
    except (OSError, json.JSONDecodeError):
        return False


def set_continuation_stopped(workspace: str, session_id: str) -> None:
    grok_dir = grok_home() / "state" / "stop-continuation" / session_id
    grok_dir.mkdir(parents=True, exist_ok=True)
    (grok_dir / "stopped").write_text(now_iso() + "\n", encoding="utf-8")
    mp = marker_path(workspace, session_id)
    mp.parent.mkdir(parents=True, exist_ok=True)
    existing = {}
    if mp.is_file():
        try:
            existing = json.loads(mp.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            existing = {}
    now = now_iso()
    sources = existing.get("sources") if isinstance(existing.get("sources"), dict) else {}
    sources["stop"] = {
        "state": "stopped",
        "reason": "Continuation stopped via /stop-continuation",
        "updatedAt": now,
    }
    payload = {
        "sessionID": session_id,
        "updatedAt": now,
        "sources": sources,
    }
    mp.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def clear_continuation_stopped(workspace: str, session_id: str) -> None:
    grok_flag = grok_home() / "state" / "stop-continuation" / session_id / "stopped"
    try:
        if grok_flag.is_file():
            grok_flag.unlink()
    except OSError:
        pass
    mp = marker_path(workspace, session_id)
    if not mp.is_file():
        return
    try:
        data = json.loads(mp.read_text(encoding="utf-8"))
        sources = data.get("sources") if isinstance(data.get("sources"), dict) else {}
        if "stop" in sources:
            sources["stop"] = {"state": "idle", "updatedAt": now_iso()}
            data["sources"] = sources
            data["updatedAt"] = now_iso()
            mp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    except (OSError, json.JSONDecodeError):
        pass


# --- todos from resources_state + mirror ---


INCOMPLETE_STATUSES = {"pending", "in_progress", "in-progress"}


def todos_from_resources(session_dir: Path) -> list[dict]:
    resources = session_dir / "resources_state.json"
    if not resources.is_file():
        return []
    try:
        state = json.loads(resources.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    todos: list[dict] = []
    for key, entry in (state or {}).items():
        if not isinstance(entry, dict):
            continue
        if "TodoState" not in key and "todo_write" not in key:
            continue
        raw = entry.get("state")
        if not raw:
            continue
        try:
            todo_data = json.loads(raw) if isinstance(raw, str) else raw
        except json.JSONDecodeError:
            continue
        items = todo_data.get("todos") if isinstance(todo_data, dict) else None
        if not isinstance(items, list):
            continue
        for t in items:
            if isinstance(t, dict):
                todos.append(t)
    return todos


def incomplete_todos(todos: list[dict]) -> list[dict]:
    out = []
    for t in todos:
        status = str(t.get("status") or "").lower()
        if status in INCOMPLETE_STATUSES:
            out.append(t)
        elif status not in ("completed", "cancelled", "blocked", "deleted"):
            out.append(t)
    return out


def mirror_todos(workspace: str, session_id: str, todos: list[dict]) -> None:
    if not workspace:
        return
    dest = Path(workspace) / TODO_MIRROR_DIR / f"{session_id}.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    payload = {"session_id": session_id, "updated_at": now_iso(), "todos": todos}
    dest.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


# --- boulder.json ---


def boulder_path(workspace: str) -> Path:
    return Path(workspace) / BOULDER_DIR / BOULDER_FILE


def read_boulder(workspace: str) -> dict | None:
    path = boulder_path(workspace)
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else None
    except (OSError, json.JSONDecodeError):
        return None


def write_boulder(workspace: str, state: dict) -> bool:
    path = boulder_path(workspace)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
        return True
    except OSError:
        return False


def get_works(state: dict) -> list[dict]:
    works = state.get("works")
    if isinstance(works, dict):
        return [w for w in works.values() if isinstance(w, dict)]
    return []


def get_work_for_session(state: dict, session_id: str) -> dict | None:
    for work in get_works(state):
        ids = work.get("session_ids") or []
        if session_id in ids:
            return work
    if session_id in (state.get("session_ids") or []):
        return {
            "work_id": state.get("active_work_id") or "legacy",
            "active_plan": state.get("active_plan"),
            "plan_name": state.get("plan_name"),
            "status": state.get("status"),
            "started_at": state.get("started_at"),
            "ended_at": state.get("ended_at"),
            "elapsed_ms": state.get("elapsed_ms"),
            "session_ids": list(state.get("session_ids") or []),
            "session_origins": dict(state.get("session_origins") or {}),
            "agent": state.get("agent"),
            "worktree_path": state.get("worktree_path"),
            "task_sessions": dict(state.get("task_sessions") or {}),
        }
    return None


def resolve_plan_path(workspace: str, state: dict, work: dict | None = None) -> Path | None:
    plan = (work or state).get("active_plan") or state.get("active_plan")
    if not plan:
        return None
    base = Path(workspace)
    plan_path = Path(plan) if Path(plan).is_absolute() else base / plan
    wt = (work or state).get("worktree_path") or state.get("worktree_path")
    if wt:
        wt_path = Path(wt) if Path(wt).is_absolute() else base / wt
        try:
            rel = plan_path.resolve().relative_to(base.resolve())
            candidate = wt_path / rel
            if candidate.is_file():
                return candidate
        except ValueError:
            pass
    return plan_path if plan_path.is_file() else None


def get_plan_progress(plan_path: Path) -> dict:
    if not plan_path or not plan_path.is_file():
        return {"total": 0, "completed": 0, "is_complete": False}
    try:
        lines = plan_path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return {"total": 0, "completed": 0, "is_complete": False}
    todo_h = re.compile(r"^##\s+TODOs\b", re.I)
    final_h = re.compile(r"^##\s+Final Verification Wave\b", re.I)
    h2 = re.compile(r"^##\s+")
    unchecked = re.compile(r"^(\s*)[-*]\s*\[\s*\]\s*(.+)$")
    checked = re.compile(r"^(\s*)[-*]\s*\[[xX]\]\s*(.+)$")
    todo_task = re.compile(r"^\d+\.\s+")
    final_task = re.compile(r"^F\d+\.\s+", re.I)
    if any(todo_h.match(ln) or final_h.match(ln) for ln in lines):
        section = "other"
        total = completed = 0
        for line in lines:
            if h2.match(line):
                section = (
                    "todo"
                    if todo_h.match(line)
                    else "final-wave"
                    if final_h.match(line)
                    else "other"
                )
                continue
            if section not in ("todo", "final-wave"):
                continue
            cm = checked.match(line)
            um = None if cm else unchecked.match(line)
            m = cm or um
            if not m or m.group(1):
                continue
            body = m.group(2).strip()
            pat = todo_task if section == "todo" else final_task
            if not pat.match(body):
                continue
            total += 1
            if cm:
                completed += 1
        return {
            "total": total,
            "completed": completed,
            "is_complete": total > 0 and completed == total,
        }
    content = "\n".join(lines)
    u = len(re.findall(r"^[-*]\s*\[\s*\]", content, re.M))
    c = len(re.findall(r"^[-*]\s*\[[xX]\]", content, re.M))
    total = u + c
    return {
        "total": total,
        "completed": c,
        "is_complete": total > 0 and c == total,
    }


def complete_boulder(workspace: str, work_id: str | None = None) -> dict | None:
    state = read_boulder(workspace)
    if not state:
        return None
    wid = work_id or state.get("active_work_id")
    work = None
    if wid and isinstance(state.get("works"), dict):
        work = state["works"].get(wid)
    if not work:
        work = get_work_for_session(state, "") or None
    if not work and wid:
        for w in get_works(state):
            if w.get("work_id") == wid:
                work = w
                break
    if not work:
        work = state
    if str(work.get("status")) == "completed" and work.get("elapsed_ms") is not None:
        return state
    end = now_iso()
    started = work.get("started_at") or state.get("started_at")
    sm = parse_iso_ms(started)
    em = parse_iso_ms(end)
    elapsed = int(em - sm) if sm is not None and em is not None else None
    work["ended_at"] = end
    work["status"] = "completed"
    work["updated_at"] = end
    if elapsed is not None:
        work["elapsed_ms"] = elapsed
    if wid and isinstance(state.get("works"), dict) and wid in state["works"]:
        state["works"][wid] = work
    if state.get("active_work_id") == wid or not state.get("works"):
        state["status"] = "completed"
        state["ended_at"] = end
        state["updated_at"] = end
        if elapsed is not None:
            state["elapsed_ms"] = elapsed
    return state if write_boulder(workspace, state) else None


def append_session_to_boulder(workspace: str, session_id: str) -> None:
    state = read_boulder(workspace)
    if not state:
        return
    ids = list(state.get("session_ids") or [])
    if session_id not in ids:
        ids.append(session_id)
        state["session_ids"] = ids
        origins = dict(state.get("session_origins") or {})
        origins.setdefault(session_id, "direct")
        state["session_origins"] = origins
        state["updated_at"] = now_iso()
        wid = state.get("active_work_id")
        if wid and isinstance(state.get("works"), dict) and wid in state["works"]:
            w = state["works"][wid]
            w_ids = list(w.get("session_ids") or [])
            if session_id not in w_ids:
                w_ids.append(session_id)
                w["session_ids"] = w_ids
                w_origins = dict(w.get("session_origins") or {})
                w_origins.setdefault(session_id, "direct")
                w["session_origins"] = w_origins
                w["updated_at"] = now_iso()
                state["works"][wid] = w
        write_boulder(workspace, state)


def nudge_state_path(session_id: str) -> Path:
    return grok_home() / "state" / "boulder-nudge" / session_id / "nudged.json"


def was_boulder_nudged(work_id: str, session_id: str) -> bool:
    path = nudge_state_path(session_id)
    if not path.is_file():
        return False
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return work_id in (data.get("work_ids") or [])
    except (OSError, json.JSONDecodeError):
        return False


def mark_boulder_nudged(work_id: str, session_id: str) -> None:
    path = nudge_state_path(session_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    data = {}
    if path.is_file():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            data = {}
    ids = list(data.get("work_ids") or [])
    if work_id not in ids:
        ids.append(work_id)
    data["work_ids"] = ids
    data["updated_at"] = now_iso()
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def task_breakdown(work: dict) -> str:
    sessions = work.get("task_sessions") or {}
    lines = []
    for task in sorted(
        sessions.values(),
        key=lambda t: (
            int(re.sub(r"\D", "", str(t.get("task_label", "9999"))) or 9999),
            str(t.get("task_label", "")),
        ),
    ):
        if not isinstance(task, dict):
            continue
        label = task.get("task_label", "?")
        title = task.get("task_title", "")
        elapsed = task.get("elapsed_ms")
        if isinstance(elapsed, (int, float)):
            lines.append(f"- {label} {title}: {format_duration_human(int(elapsed))}")
        else:
            lines.append(f"- {label} {title}: (no timing)")
    return "\n".join(lines) if lines else "- (no task timings)"


def build_boulder_context(workspace: str, session_id: str) -> str:
    state = read_boulder(workspace)
    if not state:
        return ""
    work = get_work_for_session(state, session_id)
    if not work and session_id not in (state.get("session_ids") or []):
        return ""
    status = str(work.get("status") if work else state.get("status") or "")
    if status in ("paused", "abandoned"):
        return ""
    plan_path = resolve_plan_path(workspace, state, work)
    plan_name = (work or state).get("plan_name") or "plan"
    progress = get_plan_progress(plan_path) if plan_path else {"total": 0, "completed": 0, "is_complete": False}
    remaining = progress["total"] - progress["completed"]
    wt = (work or state).get("worktree_path")
    lines = [
        "<BOULDER_STATE>",
        f"Active plan: {plan_name}",
        f"Plan file: {(work or state).get('active_plan', '')}",
        f"Progress: {progress['completed']}/{progress['total']} tasks",
        f"Status: {status or 'active'}",
    ]
    if wt:
        lines.append(f"Worktree: {wt}")
    if remaining > 0:
        lines.append(f"{remaining} task(s) remaining — read the plan and continue.")
    lines.append("</BOULDER_STATE>")
    return "\n".join(lines)


def evaluate_todo_stop(stdin_path: str, session_id: str, workspace: str) -> None:
    data = read_stdin_json(stdin_path)
    if should_allow_stop(data) or not session_id:
        raise SystemExit(1)
    if is_continuation_stopped(workspace, session_id):
        raise SystemExit(1)
    session_dir = find_session_dir(session_id)
    if not session_dir:
        raise SystemExit(1)
    todos = todos_from_resources(session_dir)
    incomplete = incomplete_todos(todos)
    if workspace:
        mirror_todos(workspace, session_id, todos)
    if not incomplete:
        raise SystemExit(1)
    total = len(todos)
    done = total - len(incomplete)
    todo_lines = "\n".join(
        f"- [{t.get('status', 'pending')}] {(t.get('content') or t.get('id') or 'todo')[:200]}"
        for t in incomplete
    )
    msg = (
        f"{TODO_CONTINUATION_PROMPT}\n\n"
        f"[Status: {done}/{total} completed, {len(incomplete)} remaining]\n\n"
        f"Remaining tasks:\n{todo_lines}"
    )
    print(msg.strip())
    raise SystemExit(0)


def evaluate_boulder_stop(stdin_path: str, session_id: str, workspace: str) -> None:
    data = read_stdin_json(stdin_path)
    if should_allow_stop(data) or not session_id or not workspace:
        raise SystemExit(1)
    if is_continuation_stopped(workspace, session_id):
        raise SystemExit(1)
    state = read_boulder(workspace)
    if not state:
        raise SystemExit(1)
    work = get_work_for_session(state, session_id)
    if not work and session_id not in (state.get("session_ids") or []):
        raise SystemExit(1)
    append_session_to_boulder(workspace, session_id)
    status = str((work or state).get("status") or "")
    if status in ("paused", "abandoned"):
        raise SystemExit(1)
    plan_path = resolve_plan_path(workspace, state, work)
    progress = get_plan_progress(plan_path) if plan_path else {"total": 0, "completed": 0, "is_complete": False}
    plan_name = (work or state).get("plan_name") or "plan"
    work_id = (work or state).get("work_id") or state.get("active_work_id") or "default"

    if progress["is_complete"]:
        complete_boulder(workspace, work_id if work else None)
        if was_boulder_nudged(str(work_id), session_id):
            raise SystemExit(1)
        w = work or state
        elapsed = w.get("elapsed_ms")
        if not isinstance(elapsed, int):
            sm = parse_iso_ms(w.get("started_at"))
            em = parse_iso_ms(w.get("ended_at")) or parse_iso_ms(now_iso())
            elapsed = int(em - sm) if sm and em else 0
        msg = BOULDER_COMPLETE_PROMPT.format(
            plan_name=plan_name,
            elapsed_human=format_duration_human(int(elapsed or 0)),
            task_breakdown=task_breakdown(w if isinstance(w, dict) else {}),
        )
        mark_boulder_nudged(str(work_id), session_id)
        print(msg.strip())
        raise SystemExit(0)

    remaining = progress["total"] - progress["completed"]
    wt = (work or state).get("worktree_path")
    msg = BOULDER_CONTINUATION_PROMPT.format(plan_name=plan_name)
    msg += f"\n\n[Status: {progress['completed']}/{progress['total']} completed, {remaining} remaining]"
    msg += f"\n\nPlan file: {(work or state).get('active_plan', '')}"
    if wt:
        msg += f"\n\n[Worktree: {wt}]"
    print(msg.strip())
    raise SystemExit(0)


def main() -> None:
    action = os.environ.get("OMO_ACTION", "")
    if action == "evaluate_todo_stop":
        evaluate_todo_stop(
            sys.argv[1] if len(sys.argv) > 1 else "",
            os.environ.get("GROK_SESSION_ID", ""),
            os.environ.get("GROK_WORKSPACE_ROOT", ""),
        )
    if action == "evaluate_boulder_stop":
        evaluate_boulder_stop(
            sys.argv[1] if len(sys.argv) > 1 else "",
            os.environ.get("GROK_SESSION_ID", ""),
            os.environ.get("GROK_WORKSPACE_ROOT", ""),
        )
    if action == "build_boulder_context":
        ctx = build_boulder_context(
            os.environ.get("GROK_WORKSPACE_ROOT", ""),
            os.environ.get("GROK_SESSION_ID", ""),
        )
        if ctx:
            print(ctx)
        raise SystemExit(0)
    if action == "set_continuation_stopped":
        set_continuation_stopped(
            os.environ.get("GROK_WORKSPACE_ROOT", ""),
            os.environ.get("GROK_SESSION_ID", ""),
        )
        raise SystemExit(0)
    if action == "clear_continuation_stopped":
        clear_continuation_stopped(
            os.environ.get("GROK_WORKSPACE_ROOT", ""),
            os.environ.get("GROK_SESSION_ID", ""),
        )
        raise SystemExit(0)
    if action == "clear_boulder":
        wp = boulder_path(os.environ.get("GROK_WORKSPACE_ROOT", ""))
        try:
            if wp.is_file():
                wp.unlink()
        except OSError:
            pass
        raise SystemExit(0)
    if action == "is_continuation_stopped":
        workspace = os.environ.get("GROK_WORKSPACE_ROOT", "")
        session_id = os.environ.get("GROK_SESSION_ID", "")
        print("1" if is_continuation_stopped(workspace, session_id) else "0")
        raise SystemExit(0)
    if action == "mirror_todos":
        session_id = os.environ.get("GROK_SESSION_ID", "")
        workspace = os.environ.get("GROK_WORKSPACE_ROOT", "")
        session_dir = find_session_dir(session_id)
        if session_dir and workspace:
            todos = todos_from_resources(session_dir)
            mirror_todos(workspace, session_id, todos)
        raise SystemExit(0)
    raise SystemExit(2)


if __name__ == "__main__":
    main()