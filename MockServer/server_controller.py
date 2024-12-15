from fastapi import FastAPI, Response, UploadFile, File, HTTPException
from fastapi.responses import StreamingResponse, RedirectResponse, FileResponse
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

    @app.get("/test")
    async def test(protocol: str = "Unknown"):
        return Response(
            content=json.dumps({
                "status": "ok",
                "protocol": protocol,
                "timestamp": "test"
            }),
            media_type="application/json"
        )

    @app.get("/download/{size_mb}")
    async def download(size_mb: int):
        """Generate and serve a file of specified size in MB"""
        if size_mb <= 0 or size_mb > 100:  # limit max size to 100MB
            raise HTTPException(status_code=400, detail="Size must be between 1 and 100 MB")
        
        async def generate_content():
            chunk_size = 1024 * 1024  # 1MB chunks
            for _ in range(size_mb):
                yield os.urandom(chunk_size)
        
        return StreamingResponse(
            generate_content(),
            media_type="application/octet-stream",
            headers={"Content-Disposition": f"attachment; filename=test_{size_mb}mb.bin"}
        )

    @app.get("/download/slow")
    async def download_slow(size_kb: int = 1024, speed_kbps: int = 100):
        """
        Generate and serve a file with controlled download speed
        size_kb: Total size in KB
        speed_kbps: Speed in KB per second
        """
        if size_kb <= 0 or size_kb > 102400:  # limit max size to 100MB
            raise HTTPException(status_code=400, detail="Size must be between 1 and 102400 KB")
        if speed_kbps <= 0 or speed_kbps > 1024:  # limit max speed to 1MB/s
            raise HTTPException(status_code=400, detail="Speed must be between 1 and 1024 KB/s")
        
        async def generate_slow_content():
            chunk_size = speed_kbps * 1024  # bytes per second
            remaining_size = size_kb * 1024  # total bytes
            
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
                "Content-Disposition": f"attachment; filename=slow_{size_kb}kb_{speed_kbps}kbps.bin",
                "X-Download-Size": str(size_kb * 1024),
                "X-Download-Speed": str(speed_kbps * 1024)
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
