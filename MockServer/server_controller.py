from fastapi import FastAPI, Response, UploadFile, File, HTTPException, Request, Body
from fastapi.responses import StreamingResponse, RedirectResponse, FileResponse, JSONResponse
from starlette.responses import Response as StarletteResponse
from starlette.datastructures import MutableHeaders
from starlette.types import Message
import json
import os
import asyncio
from typing import Optional, Any
import gzip
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

def create_app():
    app = FastAPI()

    @app.middleware("http")
    async def log_request_info(request: Request, call_next):
        """Log request and response information"""
        # Get request details before processing
        method = request.method
        path = request.url.path
        client = request.client.host if request.client else "unknown"
        protocol = "HTTP/2" if request.headers.get("upgrade") == "h2c" else "HTTP/1.1"

        # Process the request
        response = await call_next(request)

        # Log the summary
        logger.info(
            f"Request Summary: {protocol} | {method} {path} | "
            f"Client: {client} | "
            f"Status: {response.status_code}"
        )

        return response

    @app.get("/hello")
    async def root(body: Optional[Any] = Body(None)):
        """
        Simple hello world endpoint using FastAPI's Body parameter for proper HTTP/2 handling
        """
        return {"message": "Hello World!"}

    @app.api_route("/echo", methods=["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"])
    async def echo(request: Request):
        """
        Echo back request details including headers, method, and body
        For binary data, only return the content length
        For HEAD requests, return same headers as GET but no body
        """
        # Get headers (excluding connection headers that FastAPI handles)
        headers = dict(request.headers)
        excluded_headers = ['connection', 'content-length', 'transfer-encoding']
        headers = {k: v for k, v in headers.items() if k.lower() not in excluded_headers}

        # Get request body
        body = await request.body()
        content_type = request.headers.get('content-type', '').lower()

        # Handle body based on content type
        if body:
            if any(t in content_type for t in ['text', 'json', 'xml', 'form-data', 'x-www-form-urlencoded']):
                body_content = body.decode('utf-8', errors='replace')
            else:
                body_content = f"<binary data of length {len(body)} bytes>"
        else:
            body_content = None

        response_data = {
            "method": request.method,
            "url": str(request.url),
            "headers": headers,
            "query_params": dict(request.query_params),
            "body": body_content
        }

        response_headers = {
            "X-Echo-Server": "FastAPI"
        }

        if request.method == "OPTIONS":
            response_headers.update({
                "Access-Control-Allow-Origin": headers.get("origin", "*"),
                "Access-Control-Allow-Methods": headers.get("access-control-request-method", "GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS"),
                "Access-Control-Allow-Headers": headers.get("access-control-request-headers", "*"),
                "Access-Control-Max-Age": "86400"
            })

        return JSONResponse(
            content=response_data,
            headers=response_headers
        )

    @app.post("/upload/post/slow")
    async def upload_file_slow(file: UploadFile = File(...)):
        """Handle file upload with simulated slow processing"""
        chunk_size = 200 * 1024
        total_size = 0

        while chunk := await file.read(chunk_size):
            total_size += len(chunk)
            await asyncio.sleep(1)  # Simulate slow processing

        return {
            "filename": file.filename,
            "content_type": file.content_type,
            "size": total_size
        }


    @app.put("/upload/put/slow")
    async def upload_file_slow(request: Request):
        """Handle file upload with simulated slow processing"""
        chunk_size = 200 * 1024
        total_size = 0

        content_type = request.headers.get("Content-Type", "application/octet-stream")

        # Read the body data in chunks
        async for chunk in request.stream():
            total_size += len(chunk)
            await asyncio.sleep(1)  # Simulate slow processing

        return {
            "content_type": content_type,
            "size": total_size
        }


    @app.get("/download/1MB_data_at_200KBps_speed")
    async def download_slow(body: Optional[Any] = Body(None)):
        """
        Generate and serve a file with controlled download speed
        """
        async def generate_slow_content():
            chunk_size = 200 * 1024  # bytes per second
            remaining_size = 1 * 1024 * 1024  # total bytes

            while remaining_size > 0:
                # Calculate the actual chunk size for this iteration
                current_chunk_size = min(chunk_size, remaining_size)
                yield os.urandom(current_chunk_size)
                remaining_size -= current_chunk_size
                # Wait 1 second before sending next chunk
                await asyncio.sleep(1)

        return StreamingResponse(
            generate_slow_content(),
            media_type="application/octet-stream",
            headers={
                "Content-Disposition": "attachment; filename=slow_1mb_200kbps.bin",
                "X-Download-Size": "1MB",
                "X-Download-Speed": "200kbps"
            }
        )

    @app.get("/stream")
    async def stream(body: Optional[Any] = Body(None)):
        """Stream a response in chunks with delays"""
        async def generate_stream():
            for i in range(10):
                await asyncio.sleep(1)  # Simulate processing delay
                yield f"chunk {i}\n".encode()

        return StreamingResponse(
            generate_stream(),
            media_type="text/plain"
        )

    @app.get("/redirect")
    async def redirect(body: Optional[Any] = Body(None)):
        """
        Redirect to /echo endpoint with 302 status code
        """
        return RedirectResponse(
            url="/echo",
            status_code=302,
            headers={"X-Original-Path": "/redirect"}
        )

    @app.get("/redirect_to")
    async def redirect_to(from_url: str = None):
        """
        Redirect to the specified URL provided in the 'from' parameter
        If no URL is provided, returns a 400 error
        """
        if not from_url:
            raise HTTPException(status_code=400, detail="Missing 'from' parameter")
        return RedirectResponse(url=from_url, status_code=302)

    @app.get("/redirect_chain")
    async def redirect_chain(body: Optional[Any] = Body(None)):
        """
        Create a redirect chain: /redirect_chain -> /redirect -> /echo
        """
        return RedirectResponse(
            url="/redirect",
            status_code=302,
            headers={
                "X-Original-Path": "/redirect_chain",
                "Connection": "keep-alive",
                "Keep-Alive": "timeout=5, max=1000"
            }
        )

    @app.get("/get/gzip_response")
    async def gzip_response(body: Optional[Any] = Body(None)):
        """Return a gzipped JSON response"""
        content = {"message": "This is a gzipped response"}
        buf = gzip.compress(json.dumps(content).encode())
        return Response(
            content=buf,
            media_type="application/json",
            headers={"Content-Encoding": "gzip"}
        )

    @app.get("/timeout/request")
    async def timeout_request():
        # Sleep for 2 seconds to simulate a slow response
        await asyncio.sleep(2)
        return {"message": "Response after delay"}

    return app

app = create_app()
