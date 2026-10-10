#!/usr/bin/env python3
"""Loopback bridge from the eco cons Jev advisor widget to TypeSafe's System One API.

The game's Lua speaks plain HTTP only and must not hold the API key. This process listens on
127.0.0.1, adds the key from the TYPESAFE_API_KEY environment variable and forwards
POST /systemone bodies to https://api.typesafe.ai/v1/systemone.

    python scripts/jev_bridge.py            # needs TYPESAFE_API_KEY
    python scripts/jev_bridge.py --mock     # canned answers, no network, for trying the widget
"""
import argparse
import json
import os
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM_URL = "https://api.typesafe.ai/v1/systemone"
DEFAULT_MODEL = "jev-latest"
DEFAULT_PORT = 8377
MAX_BODY_BYTES = 256 * 1024
UPSTREAM_TIMEOUT_SECONDS = 5


def mock_answers(questions):
    """Stand-in answers: the first option, an undecided noul, the lowest score level."""
    answers = {}
    for name, question in questions.items():
        kind = question.get("type")
        if kind == "choice":
            options = list(question.get("criteria", {}))
            answers[name] = {
                "type": "choice",
                "choice": options[0] if options else None,
                "confidence": 1.0,
                "probabilities": {option: float(index == 0) for index, option in enumerate(options)},
            }
        elif kind == "score":
            answers[name] = {"type": "score", "score": 0.0, "confidence": 1.0}
        else:
            answers[name] = {"type": "noul", "noul": 0.5}
    return {"model": "mock", "answers": answers, "usage": {"input_tokens": 0, "output_tokens": 0}}


def ask_upstream(body, api_key, url=UPSTREAM_URL):
    """Returns (status, response bytes). An unreachable upstream comes back as 502 with an error body."""
    request = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "User-Agent": "eco-cons-jev-bridge",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=UPSTREAM_TIMEOUT_SECONDS) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()
    except (urllib.error.URLError, TimeoutError) as error:
        return 502, json.dumps({"error": f"upstream unreachable: {error}"}).encode()


def make_handler(api_key, mock, upstream_url=UPSTREAM_URL):
    class Handler(BaseHTTPRequestHandler):
        def reply(self, status, payload):
            body = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path != "/health":
                return self.reply(404, {"error": "not found"})
            self.reply(200, {"ok": True, "mock": mock, "has_key": bool(api_key)})

        def do_POST(self):
            if self.path != "/systemone":
                return self.reply(404, {"error": "not found"})
            length = int(self.headers.get("Content-Length") or 0)
            if length <= 0 or length > MAX_BODY_BYTES:
                return self.reply(413, {"error": "body missing or too large"})
            try:
                request = json.loads(self.rfile.read(length))
                questions = request["questions"]
            except (ValueError, KeyError, TypeError):
                return self.reply(400, {"error": "body must be JSON with state and questions"})
            request.setdefault("model", DEFAULT_MODEL)

            started = time.monotonic()
            if mock:
                status, body = 200, json.dumps(mock_answers(questions)).encode()
            elif not api_key:
                status, body = 503, json.dumps({"error": "TYPESAFE_API_KEY is not set"}).encode()
            else:
                status, body = ask_upstream(json.dumps(request).encode(), api_key, upstream_url)
            elapsed_ms = (time.monotonic() - started) * 1000
            print(
                f"{time.strftime('%H:%M:%S')} {status} {elapsed_ms:.0f} ms {len(questions)} questions {length} bytes in",
                flush=True,
            )
            self.reply(status, body)

        def log_message(self, *_):  # the per-request line above replaces the default access log
            pass

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=int(os.environ.get("JEV_BRIDGE_PORT", DEFAULT_PORT)))
    parser.add_argument("--mock", action="store_true", help="answer locally without calling TypeSafe")
    arguments = parser.parse_args()

    api_key = os.environ.get("TYPESAFE_API_KEY", "")
    server = ThreadingHTTPServer(("127.0.0.1", arguments.port), make_handler(api_key, arguments.mock))
    mode = "mock" if arguments.mock else ("live" if api_key else "NO KEY: requests will get 503")
    print(f"jev bridge on http://127.0.0.1:{arguments.port} ({mode})", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
