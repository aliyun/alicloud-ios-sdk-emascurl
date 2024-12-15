from fastapi import FastAPI, Response, UploadFile, File, HTTPException, Request
from fastapi.responses import StreamingResponse, RedirectResponse, FileResponse, JSONResponse
import json
import os
import asyncio
from typing import Optional
import aiofiles

def create_app():
    app = FastAPI()

    @app.get("/")
    async def root():
        return {"message": "Hello World!"}

    @app.api_route("/echo", methods=["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"])
    async def echo(request: Request):
        """
        Echo back request details including headers, method, and body
        For binary data, only return the content length
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
        
        return JSONResponse(
            content=response_data,
            headers={"X-Echo-Server": "FastAPI"}
        )

    @app.get("/download/1MB_data_at_200KBps_speed")
    async def download_slow():
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

    @app.post("/upload")
    async def upload(file: UploadFile = File(...)):
        """Handle file upload and return file info"""
        contents = await file.read()
        size = len(contents)
        return {
            "filename": file.filename,
            "content_type": file.content_type,
            "size_bytes": size
        }

    @app.get("/stream")
    async def stream():
        """Stream a response in chunks with delays"""
        async def generate_stream():
            for i in range(10):
                await asyncio.sleep(1)  # Simulate processing delay
                yield f"chunk {i}\n".encode()
        
        return StreamingResponse(
            generate_stream(),
            media_type="text/plain"
        )

    @app.get("/redirect/{n}")
    async def redirect(n: int, final_url: Optional[str] = None):
        """Redirect n times before reaching the final destination"""
        if n <= 0:
            return {"message": "Reached final destination", "redirects": "completed"}
        
        next_n = n - 1
        next_url = final_url if next_n == 0 else f"/redirect/{next_n}"
        if final_url and next_n == 0:
            return RedirectResponse(url=final_url)
        return RedirectResponse(url=next_url)

    return app

app = create_app()
