from hypercorn.config import Config
from hypercorn.asyncio import serve
import asyncio
from server_controller import create_app

app = create_app()

@app.middleware("http")
async def add_protocol_info(request, call_next):
    response = await call_next(request)
    return response

async def main():
    config = Config()
    config.bind = ["0.0.0.0:8002"]  # Different port from HTTP/1.1
    config.alpn_protocols = ["h2"]   # Only use HTTP/2
    
    await serve(app, config)

if __name__ == "__main__":
    asyncio.run(main())
