import html
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


HOST = os.getenv("APP_HOST", "0.0.0.0")
PORT = int(os.getenv("APP_PORT", "8080"))
README = Path(__file__).with_name("README.md")


class Handler(BaseHTTPRequestHandler):
    server_version = "AGIMesh/1.0"

    def send_body(self, status, content_type, body):
        payload = body.encode("utf-8")

        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'none'; style-src 'unsafe-inline'",
        )
        self.end_headers()

        self.wfile.write(payload)

    def do_GET(self):
        if self.path == "/health":
            self.send_body(
                200,
                "application/json",
                json.dumps({"status": "healthy"}),
            )
            return

        if self.path == "/":
            if README.exists():
                text = README.read_text(encoding="utf-8")
            else:
                text = "Windows AGI Mesh"

            page = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Windows AGI Mesh</title>
  <style>
    body {{
      max-width: 960px;
      margin: 3rem auto;
      padding: 0 1.5rem;
      font: 16px/1.6 system-ui;
      color: #172033;
    }}

    pre {{
      white-space: pre-wrap;
      overflow-wrap: anywhere;
      background: #f4f7fb;
      padding: 1.5rem;
      border-radius: 12px;
    }}
  </style>
</head>
<body>
  <h1>Windows AGI Mesh</h1>
  <pre>{html.escape(text)}</pre>
</body>
</html>"""

            self.send_body(
                200,
                "text/html; charset=utf-8",
                page,
            )
            return

        self.send_body(
            404,
            "application/json",
            json.dumps({"error": "not found"}),
        )

    def log_message(self, format, *args):
        print(
            f"{self.client_address[0]} - {format % args}",
            flush=True,
        )


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), Handler)

    print(
        f"Windows AGI Mesh listening on http://{HOST}:{PORT}",
        flush=True,
    )

    server.serve_forever()
  
