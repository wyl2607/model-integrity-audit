#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import sys
import time


VALID_MODELS = {
    "gpt-5.5": {"reasoning": 0, "repeat": 9},
    "gpt-5.4": {"reasoning": 0, "repeat": 13},
    "gpt-5.4-mini": {"reasoning": 48, "repeat": 17},
    "gpt-5.3-codex": {"reasoning": 24, "repeat": 11},
    "gpt-5.2": {"reasoning": 16, "repeat": 10},
}

VALID_REASONING = {"none", "minimal", "low", "medium", "high", "xhigh"}
MOCK_MODE = os.environ.get("MOCK_RESPONSES_MODE", "normal")


class Handler(BaseHTTPRequestHandler):
    server_version = "MockResponsesAPI/1.0"

    def log_message(self, fmt, *args):
        return

    def _json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _raw(self, status, body, content_type="application/json"):
        encoded = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self):
        if self.path == "/health":
            self._json(200, {"ok": True})
            return
        self._json(404, {"error": {"message": "not found"}})

    def do_POST(self):
        if self.path != "/v1/responses":
            self._json(404, {"error": {"message": "not found"}})
            return

        if MOCK_MODE == "server_error":
            self._json(500, {"error": {"message": "mock server error"}})
            return

        if MOCK_MODE == "malformed_json":
            self._raw(200, '{"id":"resp_mock_broken", "model":')
            return

        if MOCK_MODE == "timeout":
            time.sleep(3)

        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            self._json(401, {"error": {"message": "missing bearer token"}})
            return

        length = int(self.headers.get("Content-Length", "0"))
        try:
            request = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self._json(400, {"error": {"message": "invalid json"}})
            return

        model = request.get("model", "")
        if model not in VALID_MODELS:
            self._json(404, {"error": {"message": f"model {model} not found"}})
            return

        effort = request.get("reasoning", {}).get("effort", "medium")
        if effort not in VALID_REASONING:
            self._json(400, {"error": {"message": "Invalid value for reasoning.effort. Supported values are none, minimal, low, medium, high, xhigh."}})
            return

        fingerprint = VALID_MODELS[model]
        text = (f"Mock response for {model}. LRU vs LFU warm-up bias. " * fingerprint["repeat"]).strip()
        output_tokens = max(8, len(text.split()))
        reasoning_tokens = fingerprint["reasoning"]
        input_tokens = max(1, len(str(request.get("input", "")).split()))

        response = {
            "id": f"resp_mock_{int(time.time() * 1000)}",
            "object": "response",
            "model": "gpt-5.4-mini" if MOCK_MODE == "model_mismatch" else model,
            "output_text": text,
            "usage": {
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
                "output_tokens_details": {"reasoning_tokens": reasoning_tokens},
                "total_tokens": input_tokens + output_tokens + reasoning_tokens,
            },
        }
        if MOCK_MODE == "missing_usage":
            response.pop("usage")
        self._json(200, response)


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"mock_responses_api=http://127.0.0.1:{port}/v1", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
