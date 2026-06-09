from fastapi import FastAPI

app = FastAPI()

@app.get("/users")
def get_users():
    return {
        "service": "users-service",
        "users": [
            {"id": 1, "name": "khaja"},
            {"id": 2, "name": "ibrahim"}
        ]
    }