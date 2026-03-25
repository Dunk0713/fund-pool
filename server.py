#!/usr/bin/env python3
"""Local proxy server — serves static files and proxies iFind MCP API calls.

Usage: python server.py
Then open: http://localhost:3000/index.html
"""

import http.server
import json
import os
import ssl
import urllib.request

PORT = 3000
SERVE_DIR = os.path.dirname(os.path.abspath(__file__))

# Read iFind token from .mcp.json (same directory as this script)
def _load_token():
    cfg = os.path.join(SERVE_DIR, '.mcp.json')
    try:
        with open(cfg, encoding='utf-8') as f:
            d = json.load(f)
        return d['mcpServers']['hexin-ifind-ds-fund-mcp']['headers']['Authorization']
    except Exception:
        return None

IFIND_URL = 'https://api-mcp.51ifind.com:8643/ds-mcp-servers/hexin-ifind-ds-fund-mcp'
IFIND_TOKEN = _load_token()


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=SERVE_DIR, **kwargs)

    # ── CORS preflight ──────────────────────────────────────────────────────
    def do_OPTIONS(self):
        self.send_response(200)
        self._cors_headers()
        self.end_headers()

    # ── iFind proxy ─────────────────────────────────────────────────────────
    def do_POST(self):
        if self.path != '/api/ifind':
            self.send_error(404)
            return

        if not IFIND_TOKEN:
            self._json_response(500, {'error': 'iFind token not found in .mcp.json'})
            return

        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length)

        req = urllib.request.Request(
            IFIND_URL,
            data=body,
            headers={
                'Authorization': IFIND_TOKEN,
                'Content-Type': 'application/json',
            },
            method='POST',
        )
        ctx = ssl.create_default_context()
        try:
            with urllib.request.urlopen(req, context=ctx, timeout=15) as r:
                data = r.read()
            self._json_response(200, raw=data)
        except urllib.error.HTTPError as e:
            self._json_response(502, {'error': f'iFind HTTP {e.code}: {e.reason}'})
        except Exception as e:
            self._json_response(502, {'error': str(e)})

    # ── helpers ─────────────────────────────────────────────────────────────
    def _json_response(self, code, obj=None, raw=None):
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self._cors_headers()
        self.end_headers()
        self.wfile.write(raw if raw is not None else json.dumps(obj).encode())

    def _cors_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')

    def log_message(self, fmt, *args):
        pass  # suppress request logs


if __name__ == '__main__':
    os.chdir(SERVE_DIR)
    server = http.server.HTTPServer(('', PORT), Handler)
    print(f'✓ iFind proxy running → http://localhost:{PORT}')
    server.serve_forever()
