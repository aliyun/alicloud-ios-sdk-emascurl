import os
import sys
import signal
import multiprocessing
from hypercorn.config import Config
from hypercorn.asyncio import serve
from server_controller import app

def server_process(config):
    """Run server in a separate process"""
    import asyncio

    async def run_server():
        print(f"Starting server on {config.bind[0]}")
        print(f"Certificate file: {config.certfile}")
        print(f"Key file: {config.keyfile}")
        await serve(app, config)

    asyncio.run(run_server())

def main():
    # Common SSL/TLS Configuration
    current_dir = os.path.dirname(os.path.abspath(__file__))
    cert_file = os.path.join(current_dir, "certs/server/server.crt")
    key_file = os.path.join(current_dir, "certs/server/server.key")

    # HTTP/1.1 Server Config (plain HTTP)
    config_http11 = Config()
    config_http11.bind = ["0.0.0.0:9080"]
    config_http11.alpn_protocols = ["http/1.1"]

    # HTTP/2 Server Config (HTTPS)
    config_http2 = Config()
    config_http2.bind = ["0.0.0.0:9443"]
    config_http2.alpn_protocols = ["h2"]
    config_http2.certfile = cert_file
    config_http2.keyfile = key_file

    # Create server processes
    processes = []
    try:
        for config in [config_http11, config_http2]:
            p = multiprocessing.Process(target=server_process, args=(config,))
            p.start()
            processes.append(p)
            print(f"Started process {p.pid} for {config.bind[0]}")

        # Wait for processes
        for p in processes:
            p.join()

    except KeyboardInterrupt:
        print("\nReceived keyboard interrupt, shutting down...")
    finally:
        # Kill all processes
        for p in processes:
            if p.is_alive():
                print(f"Terminating process {p.pid}")
                p.terminate()
                p.join(timeout=1)
                if p.is_alive():
                    print(f"Force killing process {p.pid}")
                    p.kill()
                    p.join()
        print("All servers stopped.")

if __name__ == "__main__":
    # Handle Ctrl+C in the main process
    signal.signal(signal.SIGINT, lambda sig, frame: sys.exit(0))
    main()
