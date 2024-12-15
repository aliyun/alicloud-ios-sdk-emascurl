import uvicorn
from server_controller import create_app

app = create_app()

@app.middleware("http")
async def add_protocol_info(request, call_next):
    response = await call_next(request)
    return response

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8001)
