#!/usr/bin/env python3
"""Stand-in for the AI services, used by the iOS UI tests.

Serves an OpenAI-compatible chat endpoint (POST /v1/chat/completions) and an OpenRouter-style
Decisions endpoint (POST /decisions) on 127.0.0.1. Requests with a malformed body or the wrong key
get an error, so the tests also check what the app sends. Each request is logged as one JSON line.

Usage: mock_ai_server.py [port] [log_file]
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
LOG = sys.argv[2] if len(sys.argv) > 2 else None
KEY = "test-key"


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        try:
            req = json.loads(raw)
        except ValueError:
            return self._send(400, {"error": "body is not JSON"})
        auth_ok = self.headers.get("Authorization") == f"Bearer {KEY}"
        if LOG:
            with open(LOG, "a") as f:
                f.write(json.dumps({"path": self.path, "auth_ok": auth_ok, "body": req}) + "\n")
        if not auth_ok:
            return self._send(401, {"error": "wrong or missing API key"})

        if self.path == "/v1/chat/completions":
            msgs = req.get("messages")
            if not req.get("model") or not isinstance(msgs, list) or not msgs:
                return self._send(400, {"error": "model and messages are required"})
            last = msgs[-1].get("content", "")
            return self._send(200, {"choices": [{"message": {
                "role": "assistant",
                "content": f"Mock Meowy here! You asked: {last[:40]}",
            }}]})

        if self.path == "/decisions":
            q = req.get("questions", {})
            criteria = q.get("intent", {}).get("criteria", {})
            if not req.get("model") or "player_said" not in req.get("state", {}) or not criteria:
                return self._send(400, {"error": "model, state.player_said and intent criteria are required"})
            said = req["state"]["player_said"].lower()
            choice = "attack" if "attack" in said and "attack" in criteria else next(iter(criteria))
            probs = {k: (0.9 if k == choice else 0.1 / max(len(criteria) - 1, 1)) for k in criteria}
            return self._send(200, {"answers": {
                "intent": {"choice": choice, "probabilities": probs, "confidence": 0.8},
                "achieves": {"noul": 0.7},
            }})

        self._send(404, {"error": f"unknown path {self.path}"})

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
