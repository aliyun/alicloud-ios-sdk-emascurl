import os
import asyncio
from hypercorn.config import Config
from hypercorn.asyncio import serve
from fastapi import FastAPI
from server_controller import app

async def run_server(config):
    """Run a server with the given configuration"""
    print(f"Starting HTTPS server on {config.bind[0]}")
    print(f"Certificate file: {config.certfile}")
    print(f"Key file: {config.keyfile}")
    await serve(app, config)

async def main():
    # Common SSL/TLS Configuration
    current_dir = os.path.dirname(os.path.abspath(__file__))
    cert_file = os.path.join(current_dir, "certs/server/server.crt")
    key_file = os.path.join(current_dir, "certs/server/server.key")

    # HTTP/1.1 Server Config
    config_http11 = Config()
    config_http11.bind = ["0.0.0.0:9080"]  # HTTP/1.1 port
    config_http11.alpn_protocols = ["http/1.1"]
    config_http11.certfile = cert_file
    config_http11.keyfile = key_file

    # HTTP/2 Server Config
    config_http2 = Config()
    config_http2.bind = ["0.0.0.0:9443"]  # HTTP/2 port
    config_http2.alpn_protocols = ["h2"]
    config_http2.certfile = cert_file
    config_http2.keyfile = key_file

    # Run both servers concurrently
    await asyncio.gather(
        run_server(config_http11),
        run_server(config_http2)
    )

if __name__ == "__main__":
    asyncio.run(main())
