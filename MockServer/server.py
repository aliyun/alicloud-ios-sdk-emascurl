import os
import sys
import signal
import multiprocessing
import socket
import time
import threading
from hypercorn.config import Config
from hypercorn.asyncio import serve
from server_controller import app

class TimeoutServer:
    def __init__(self, host='0.0.0.0', port=9081, accept_delay=2):
        self.host = host
        self.port = port
        self.accept_delay = accept_delay
        self.server_socket = None
        self.running = False
        self.thread = None

    def start(self):
        """Start the server in a separate thread"""
        self.running = True
        self.thread = threading.Thread(target=self._run_server)
        self.thread.daemon = True
        self.thread.start()
        print(f"Timeout test server started on {self.host}:{self.port} with {self.accept_delay}s delay")

    def stop(self):
        """Stop the server"""
        self.running = False
        if self.server_socket:
            self.server_socket.close()
        if self.thread:
            self.thread.join()
        print("Timeout test server stopped")

    def _run_server(self):
        """Main server loop"""
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind((self.host, self.port))
        self.server_socket.listen(1)
        self.server_socket.settimeout(1)  # Allow checking running flag every second

        while self.running:
            try:
                # Wait for connection
                client_socket, address = self.server_socket.accept()
                print(f"Connection from {address}, delaying accept for {self.accept_delay}s")

                # Delay accepting the connection
                time.sleep(self.accept_delay)

                # Close the connection without sending any response
                client_socket.close()
                print("Connection closed after delay")

            except socket.timeout:
                continue  # Just a timeout for checking running flag
            except Exception as e:
                if self.running:  # Only log if we're still meant to be running
                    print(f"Error: {e}")

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

    # Create HTTP servers processes
    processes = []
    try:
        # Start HTTP/1.1 and HTTP/2 servers
        for config in [config_http11, config_http2]:
            p = multiprocessing.Process(target=server_process, args=(config,))
            p.start()
            processes.append(p)
            print(f"Started process {p.pid} for {config.bind[0]}")

        # Start timeout test server
        timeout_server = TimeoutServer(port=9081, accept_delay=2)
        timeout_server.start()

        # Wait for processes
        for p in processes:
            p.join()

    except KeyboardInterrupt:
        print("\nReceived keyboard interrupt, shutting down...")
    finally:
        # Stop timeout server
        timeout_server.stop()

        # Kill all HTTP server processes
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
