from fastapi import FastAPI

app = FastAPI()

@app.get("/stores")
def get_stores():
    return {
        "service": "store-service",
        "stores": [
            {"id": 1, "name": "Hyderabad Store"},
            {"id": 2, "name": "Bangalore Store"}
        ]
    }