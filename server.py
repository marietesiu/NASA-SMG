#!/usr/bin/env python3
import json
import os
import signal
import subprocess
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
FRONTEND_DIR = os.path.join(PROJECT_ROOT, "frontend")
GODOT_WEB_DIR = os.path.abspath(os.environ.get(
    "GODOT_WEB_DIR", os.path.join(PROJECT_ROOT, "..", "..", "..")
))
CATALOG_PATH = os.path.join(PROJECT_ROOT, "catalog.json")
MISSION_CONFIG_PATH = os.path.join(PROJECT_ROOT, "mission_config.json")
PORT = int(os.environ.get("PORT", "8080"))
BASE_BUDGET_M = 54.8


def load_catalog():
    with open(CATALOG_PATH, "r", encoding="utf-8") as handle:
        return json.load(handle)


def find_godot_bin():
    env_path = os.environ.get("GODOT_BIN")
    if env_path and os.path.exists(env_path):
        return env_path

    candidates = [
        "/home/mario/Downloads/Godot_v4.7.2-stable_linux.x86_64",
        "/home/mario/Downloads/Godot_v4.7.2-stable_linux.x86_64/Godot_v4.7.2-stable_linux.x86_64",
        "/home/mario/Downloads/Directory/Godot/Godot_v4.7.2-stable_linux.x86_64/Godot_v4.7.2-stable_linux.x86_64",
        "/usr/bin/godot",
        "/usr/local/bin/godot",
        "godot",
    ]
    for path in candidates:
        if path == "godot":
            return path
        if os.path.exists(path):
            return path
    return "godot"


def process_running_for_project(project_root: str) -> bool:
    try:
        result = subprocess.run(
            ["ps", "-eo", "pid,args"],
            text=True,
            capture_output=True,
            check=False,
        )
    except FileNotFoundError:
        return False

    for line in result.stdout.splitlines():
        if "--path" in line and project_root in line:
            return True
    return False


def validate_payload(payload: dict, catalog: dict):
    if not isinstance(payload, dict):
        raise ValueError("Launch payload must be a JSON object.")

    mission_id = payload.get("mission_id")
    difficulties = catalog.get("difficulties", {})
    difficulty = payload.get("difficulty")
    if difficulty not in difficulties:
        raise ValueError(f"Unsupported difficulty: {difficulty}")

    missions = catalog.get("missions", [])
    if mission_id is None:
        raise ValueError("A mission_id is required.")
    mission = next((item for item in missions if item.get("id") == mission_id), None)
    if mission is None:
        raise ValueError(f"Unknown mission_id: {mission_id}")
    if not mission.get("supported_by_runtime", False):
        raise ValueError(f"{mission.get('name', mission_id)} is not supported by the current Earth-orbit simulation.")

    selected = payload.get("selected_components")
    if not isinstance(selected, dict):
        raise ValueError("Selected components must be a dictionary keyed by category.")

    categories = {category.get("id"): category for category in catalog.get("categories", [])}
    missing_categories = categories.keys() - selected.keys()
    if missing_categories:
        raise ValueError(f"Missing component categories: {', '.join(sorted(missing_categories))}")
    for category_id, option_id in selected.items():
        if category_id not in categories:
            raise ValueError(f"Unknown category in selection: {category_id}")
        options = categories[category_id].get("options", [])
        known_option_ids = {option.get("id") for option in options}
        if option_id not in known_option_ids:
            raise ValueError(f"Unknown component option in {category_id}: {option_id}")

    difficulty_settings = difficulties[difficulty]
    budget_limit = BASE_BUDGET_M * (1.0 + float(mission.get("budget_bonus", 0.0)))
    budget_limit *= float(difficulty_settings.get("budget_multiplier", 1.0))
    total_cost = 0.0
    for category_id, option_id in selected.items():
        category = categories.get(category_id)
        if category is None:
            continue
        for option in category.get("options", []):
            if option.get("id") == option_id:
                total_cost += float(option.get("cost_m", 0.0))
                break

    if total_cost > budget_limit:
        raise ValueError(
            f"Budget exceeded: total cost {total_cost:.2f}M > limit {budget_limit:.2f}M."
        )

    return total_cost, mission, budget_limit


class LauncherHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        super().end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/api/catalog":
            self.send_json(load_catalog())
            return

        if path == "/api/health":
            self.send_json({"ok": True, "project_root": PROJECT_ROOT})
            return

        if path in ("/", ""):
            path = "/index.html"

        if path == "/godot":
            path = "/godot/index.html"

        if path.startswith("/api/"):
            self.send_error(404, "Not found")
            return

        if path.startswith("/godot/"):
            static_root = GODOT_WEB_DIR
            relative_path = path.removeprefix("/godot/")
        else:
            static_root = FRONTEND_DIR
            relative_path = path.lstrip("/")
        safe_path = os.path.normpath(os.path.join(static_root, relative_path))
        if os.path.commonpath([static_root, safe_path]) != static_root:
            self.send_error(403, "Forbidden")
            return

        if os.path.isdir(safe_path):
            safe_path = os.path.join(safe_path, "index.html")

        if not os.path.isfile(safe_path):
            self.send_error(404, "File not found")
            return

        self.send_response(200)
        content_type = self.guess_type(safe_path)
        if safe_path.endswith(".wasm"):
            content_type = "application/wasm"
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        with open(safe_path, "rb") as handle:
            self.wfile.write(handle.read())

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path != "/api/launch":
            self.send_error(404, "Not found")
            return

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(content_length)
            if not body:
                raise ValueError("Request body is empty.")
            payload = json.loads(body.decode("utf-8"))
            catalog = load_catalog()
            _, mission, budget_limit = validate_payload(payload, catalog)
            payload["target_altitude_km"] = float(mission["target_altitude_km"])
            payload["target_inclination_deg"] = float(mission["target_inclination_deg"])
            payload["budget_limit_m"] = budget_limit
            if payload.get("mission_id") == "delivering_to_mars":
                payload["cargo_mass_kg"] = 200.0
                payload["radioactive_material"] = True
                payload["cargo_warning"] = "Mars mission cargo includes 200 kg of radioactive material."

            if process_running_for_project(PROJECT_ROOT):
                raise RuntimeError("A Godot mission is already running from this project root.")

            with open(MISSION_CONFIG_PATH, "w", encoding="utf-8") as handle:
                json.dump(payload, handle, indent=2, ensure_ascii=False)
                handle.write("\n")

            godot_bin = find_godot_bin()
            command = [godot_bin, "--path", PROJECT_ROOT]
            subprocess.Popen(command, cwd=PROJECT_ROOT)
            self.send_json({"ok": True, "config_path": "mission_config.json"})
        except Exception as exc:  # pragma: no cover - HTTP error path
            self.send_json({"ok": False, "error": str(exc)}, status=400)

    def send_json(self, payload, status=200):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


if __name__ == "__main__":
    os.makedirs(FRONTEND_DIR, exist_ok=True)
    httpd = ThreadingHTTPServer(("127.0.0.1", PORT), LauncherHandler)
    print(f"Serving launcher on http://localhost:{PORT}")
    print(f"Project root: {PROJECT_ROOT}")
    print(f"Godot binary: {find_godot_bin()}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping launcher server.")
        httpd.server_close()
        sys.exit(0)
