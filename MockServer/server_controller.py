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

    @app.get("/cookie/set")
    async def set_cookie():
        """
        Set a test cookie with a fixed value
        """
        response = JSONResponse({"status": "cookie_set"})
        response.set_cookie(
            key="test_cookie",
            value="cookie_value_123",
            max_age=3600,
            path="/",
            domain=None,
            secure=False,
            httponly=True
        )
        return response

    @app.get("/cookie/verify")
    async def verify_cookie(request: Request):
        """
        Verify if the test cookie exists and has the correct value
        """
        cookie = request.cookies.get("test_cookie")
        if cookie == "cookie_value_123":
            return {"status": "valid_cookie"}
        return {"status": "invalid_cookie"}

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
        logger.info(f"Starting slow PUT upload, Content-Type: {content_type}")

        # Read the body data in chunks
        chunk_count = 0
        async for chunk in request.stream():
            chunk_count += 1
            chunk_len = len(chunk)
            total_size += chunk_len
            logger.info(f"Received chunk {chunk_count}: {chunk_len} bytes, total so far: {total_size}")
            await asyncio.sleep(1)  # Simulate slow processing

        logger.info(f"Upload complete: {total_size} bytes in {chunk_count} chunks")
        return {
            "content_type": content_type,
            "size": total_size
        }

    @app.post("/upload/post/slow_403")
    async def upload_file_slow_403(request: Request):
        """Handle file upload with slow reading and return 403 error during transfer"""
        logger.info("Starting slow upload with 403 error endpoint")
        total_size = 0

        # 直接读取原始请求体，不解析multipart
        content_length = int(request.headers.get("content-length", 0))
        logger.info(f"Content-Length: {content_length}")

        # 模拟慢速读取并在中途返回403错误
        try:
            # 读取原始字节流
            body = await request.body()
            total_size = len(body)
            logger.info(f"Read total body: {total_size} bytes")

            # 模拟分块处理
            chunk_size = 200 * 1024
            processed = 0
            while processed < total_size:
                chunk_end = min(processed + chunk_size, total_size)
                processed = chunk_end

                logger.info(f"Processed {processed} bytes of {total_size}")

                # 模拟服务器慢速处理
                await asyncio.sleep(1)

                # 当处理超过500KB后返回403错误
                if processed > 500 * 1024:
                    logger.info(f"Returning 403 error after processing {processed} bytes")
                    raise HTTPException(status_code=403, detail="Forbidden: File rejected during upload")

        except HTTPException:
            # 重新抛出HTTP异常
            raise
        except Exception as e:
            logger.error(f"Unexpected error during upload: {e}")
            raise HTTPException(status_code=500, detail="Internal server error during upload")

        # 这个分支不应该被执行到
        return {
            "status": "upload_completed",
            "size": total_size
        }

    @app.put("/upload/put/slow_403")
    async def upload_file_put_slow_403(request: Request):
        """Handle PUT upload with slow reading and return 403 error during transfer"""
        logger.info("Starting slow PUT upload with 403 error endpoint")
        total_size = 0

        content_type = request.headers.get("Content-Type", "application/octet-stream")
        content_length = int(request.headers.get("content-length", 0))
        logger.info(f"Content-Length: {content_length}")

        # 模拟慢速读取并在中途返回403错误
        try:
            # 读取原始字节流
            body = await request.body()
            total_size = len(body)
            logger.info(f"Read total body: {total_size} bytes")

            # 模拟分块处理
            chunk_size = 200 * 1024
            processed = 0
            while processed < total_size:
                chunk_end = min(processed + chunk_size, total_size)
                processed = chunk_end

                logger.info(f"Processed {processed} bytes of {total_size}")

                # 模拟服务器慢速处理
                await asyncio.sleep(1)

                # 当处理超过500KB后返回403错误
                if processed > 500 * 1024:
                    logger.info(f"Returning 403 error after processing {processed} bytes")
                    raise HTTPException(status_code=403, detail="Forbidden: File rejected during upload")

        except HTTPException:
            # 重新抛出HTTP异常
            raise
        except Exception as e:
            logger.error(f"Unexpected error during upload: {e}")
            raise HTTPException(status_code=500, detail="Internal server error during upload")

        # 这个分支不应该被执行到
        return {
            "content_type": content_type,
            "size": total_size
        }

    @app.post("/upload/post/immediate_403")
    async def upload_file_immediate_403(request: Request):
        """Immediately return 403 error without reading any data"""
        logger.info("Immediately returning 403 error for upload request")
        raise HTTPException(status_code=403, detail="Forbidden: Upload rejected immediately")

    @app.put("/upload/put/immediate_403")
    async def upload_file_put_immediate_403(request: Request):
        """Immediately return 403 error without reading any data"""
        logger.info("Immediately returning 403 error for PUT upload request")
        raise HTTPException(status_code=403, detail="Forbidden: PUT upload rejected immediately")


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

    @app.post("/half_close_test")
    async def half_close_test(request: Request):
        """
        专门用于测试半关闭场景的端点
        根据请求头中的测试场景参数执行不同的半关闭行为
        """
        test_scenario = request.headers.get("X-Test-Scenario", "default")
        logger.info(f"Half-close test scenario: {test_scenario}")

        # 读取请求体数据
        body_data = await request.body()
        content_length = len(body_data) if body_data else 0

        # 模拟处理延时
        await asyncio.sleep(1)

        if test_scenario == "bidirectional":
            # 双向半关闭场景：接收完整数据后返回响应
            return {
                "scenario": "bidirectional",
                "received_bytes": content_length,
                "status": "half_close_handled",
                "message": "Bidirectional half-close test completed"
            }
        elif test_scenario == "server_close":
            # 服务器主动关闭场景
            return {
                "scenario": "server_close",
                "received_bytes": content_length,
                "status": "server_initiated_close",
                "message": "Server initiated close after processing"
            }
        else:
            # 默认半关闭处理
            return {
                "scenario": "default",
                "received_bytes": content_length,
                "status": "normal_processing",
                "message": "Default half-close handling completed"
            }

    # 连接跟踪相关端点
    import uuid
    connection_map = {}

    @app.get("/connection_id")
    async def get_connection_id(request: Request):
        """
        返回当前连接的唯一标识符，用于验证连接复用
        """
        # 使用客户端地址和端口作为连接标识
        client_info = f"{request.client.host}:{request.client.port}" if request.client else "unknown"
        request_id = request.query_params.get("request", "unknown")

        # 检查是否是新连接
        if client_info not in connection_map:
            connection_map[client_info] = str(uuid.uuid4())
            logger.info(f"New connection established: {client_info} -> {connection_map[client_info]}")

        connection_id = connection_map[client_info]
        logger.info(f"Connection ID request #{request_id} from {client_info}: {connection_id}")

        return {
            "connection_id": connection_id,
            "client_info": client_info,
            "request_number": request_id,
            "timestamp": time.time()
        }

    @app.get("/keep_alive_test")
    async def keep_alive_test(request: Request):
        """
        测试Keep-Alive连接的端点
        """
        client_info = f"{request.client.host}:{request.client.port}" if request.client else "unknown"
        request_id = request.query_params.get("request", "unknown")

        # 跟踪连接
        if client_info not in connection_map:
            connection_map[client_info] = str(uuid.uuid4())

        connection_id = connection_map[client_info]

        logger.info(f"Keep-Alive request #{request_id} on connection {connection_id}")

        response = JSONResponse({
            "status": "keep_alive_active",
            "connection_id": connection_id,
            "request_number": request_id,
            "message": "Keep-Alive connection test successful"
        })

        # 设置Keep-Alive响应头
        response.headers["Connection"] = "keep-alive"
        response.headers["Keep-Alive"] = "timeout=5, max=100"

        return response

    @app.get("/connection_close_test")
    async def connection_close_test(request: Request):
        """
        强制关闭连接的测试端点
        """
        client_info = f"{request.client.host}:{request.client.port}" if request.client else "unknown"

        # 清理连接映射
        if client_info in connection_map:
            old_id = connection_map[client_info]
            del connection_map[client_info]
            logger.info(f"Force closing connection {old_id} for {client_info}")

        response = JSONResponse({
            "status": "connection_closing",
            "message": "Connection will be closed after this response"
        })

        # 设置Connection: close头部
        response.headers["Connection"] = "close"

        return response

    @app.get("/pipeline_test")
    async def pipeline_test(request: Request):
        """
        用于测试HTTP管道化的端点
        """
        request_id = request.query_params.get("request", "unknown")

        # 模拟快速响应以支持管道化
        return {
            "status": "pipeline_response",
            "request_number": request_id,
            "timestamp": time.time(),
            "message": "Pipeline test response"
        }

    @app.get("/connection_stats")
    async def connection_stats():
        """
        返回当前连接统计信息
        """
        return {
            "active_connections": len(connection_map),
            "connections": {k: v for k, v in connection_map.items()},
            "timestamp": time.time()
        }

    return app

app = create_app()
