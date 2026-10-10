# Run with: python tests/jev_bridge_test.py
import http.client
import importlib.util
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

spec = importlib.util.spec_from_file_location("jev_bridge", "scripts/jev_bridge.py")
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)

QUESTIONS = {
    "family": {"type": "choice", "instructions": "Which?", "criteria": {"fus": "fusion", "win": "wind"}},
    "place_now": {"type": "noul", "instructions": "Good moment?"},
}


def serve(handler):
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def call(server, method, path, body=None):
    connection = http.client.HTTPConnection("127.0.0.1", server.server_address[1], timeout=5)
    connection.request(method, path, body=body, headers={"Content-Type": "application/json"} if body else {})
    response = connection.getresponse()
    payload = json.loads(response.read())
    connection.close()
    return response.status, payload


def test_mock_answers_without_network():
    server = serve(bridge.make_handler("", mock=True))
    status, payload = call(server, "POST", "/systemone", json.dumps({"state": {}, "questions": QUESTIONS}))
    assert status == 200, status
    assert payload["answers"]["family"]["choice"] == "fus", payload
    assert payload["answers"]["place_now"]["noul"] == 0.5, payload
    server.shutdown()


def test_forwards_with_key_and_passes_upstream_status_through():
    seen = {}

    class Upstream(BaseHTTPRequestHandler):
        def do_POST(self):
            seen["authorization"] = self.headers.get("Authorization")
            seen["body"] = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            body = json.dumps({"error": "slow down"}).encode()
            self.send_response(429)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_):
            pass

    upstream = serve(Upstream)
    upstream_url = f"http://127.0.0.1:{upstream.server_address[1]}/v1/systemone"
    server = serve(bridge.make_handler("secret-key", mock=False, upstream_url=upstream_url))
    status, payload = call(server, "POST", "/systemone", json.dumps({"state": "x", "questions": QUESTIONS}))
    assert status == 429 and payload == {"error": "slow down"}, (status, payload)
    assert seen["authorization"] == "Bearer secret-key", seen
    assert seen["body"]["model"] == "jev-latest", "model is defaulted"
    assert seen["body"]["questions"] == QUESTIONS, "questions are forwarded unchanged"
    server.shutdown()
    upstream.shutdown()


def test_refuses_what_it_should():
    server = serve(bridge.make_handler("", mock=False))
    assert call(server, "POST", "/systemone", json.dumps({"state": "x", "questions": QUESTIONS}))[0] == 503, "no key"
    assert call(server, "POST", "/systemone", "not json")[0] == 400
    assert call(server, "POST", "/systemone", json.dumps({"state": "x"}))[0] == 400, "questions are required"
    assert call(server, "POST", "/elsewhere", "{}")[0] == 404
    assert call(server, "POST", "/systemone", "x" * (bridge.MAX_BODY_BYTES + 1))[0] == 413
    status, health = call(server, "GET", "/health")
    assert status == 200 and health == {"ok": True, "mock": False, "has_key": False}, health
    server.shutdown()


def test_unreachable_upstream_is_a_502():
    status, body = bridge.ask_upstream(b"{}", "key", url="http://127.0.0.1:9/v1/systemone")
    assert status == 502 and "upstream unreachable" in json.loads(body)["error"], (status, body)


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
        print(f"  [PASS] {test.__name__}")
    print(f"Passed {len(tests)} jev_bridge tests.")
