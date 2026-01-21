from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import requests
import json
import asyncio

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- In-Memory Storage ---
hazards = [
    {"id": 1, "lat": 37.7749, "lng": -122.4194, "type": "pothole", "tag": "Pothole", "description": "Big pothole on right lane", "verified": False, "timestamp": "2023-10-27T10:00:00Z"},  # Sample
]
speed_zones = [
    {"id": 1, "lat": 37.7749, "lng": -122.4194, "radius": 500, "limit": 30}, # Sample city zone
    {"id": 2, "lat": 37.7849, "lng": -122.4094, "radius": 1000, "limit": 50}, # Sample highway part
]

# --- Models ---
class Hazard(BaseModel):
    lat: float
    lng: float
    type: str # 'pothole', 'accident', 'closure' (This can act as the 'tag' or we treat 'tag' separately? Let's treat 'type' as the internal category and add 'tag' as user-facing label)
    tag: str # User selected tag
    description: str
    verified: bool = False

class AuthLogin(BaseModel):
    username: str
    password: str

# --- WebSockets ---
class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)

    async def broadcast(self, message: str):
        for connection in self.active_connections:
            await connection.send_text(message)

manager = ConnectionManager()

# --- Endpoints ---

@app.get("/")
def read_root():
    return {"status": "SafeRoute MVP Backend Running"}

@app.get("/search")
def search_places(q: str, lat: Optional[float] = None, lon: Optional[float] = None):
    """Proxy to Nominatim with optional location biasing"""
    url = "https://nominatim.openstreetmap.org/search"
    headers = {'User-Agent': 'SafeRouteMVP/1.0'}
    params = {'q': q, 'format': 'json', 'addressdetails': 1, 'limit': 5}
    
    if lat is not None and lon is not None:
        # Define a viewbox approx 0.5 degrees (~50km) around the user
        # Format: <x1>,<y1>,<x2>,<y2> (left, top, right, bottom)
        viewbox = f"{lon-0.5},{lat+0.5},{lon+0.5},{lat-0.5}"
        params['viewbox'] = viewbox
        params['bounded'] = 1 # Prefer results in this box
        
    try:
        response = requests.get(url, params=params, headers=headers)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/route")
def get_route(start: str, end: str, alternatives: str = "false", steps: str = "false", profile: str = "car"):
    """
    Proxy to OSRM. 
    Input format: "lat,lng" 
    OSRM expects: "lng,lat"
    """
    try:
        start_lat, start_lng = start.split(',')
        end_lat, end_lng = end.split(',')
        
        # Map profile to OSRM modes
        osrm_mode = "driving"
        if profile == "bike":
            osrm_mode = "bike" # OSRM public demo sometimes uses 'cycling' or 'bike', let's try 'driving' as fallback if not sure, but 'bike' is common in some setups. 
            # Actually standard OSRM demo server profiles are: driving, walking, cycling.
            osrm_mode = "cycling"
        elif profile == "foot":
            osrm_mode = "walking"
        
        # OSRM url format: {lng},{lat};{lng},{lat}
        osrm_url = f"http://router.project-osrm.org/route/v1/{osrm_mode}/{start_lng},{start_lat};{end_lng},{end_lat}?overview=full&geometries=geojson&alternatives={alternatives}&steps={steps}"
        
        response = requests.get(osrm_url)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/speed-zones")
def get_speed_zones():
    return speed_zones

@app.get("/hazards")
def get_hazards():
    return hazards

@app.post("/hazards")
async def create_hazard(hazard: Hazard):
    new_hazard = hazard.dict()
    new_hazard["id"] = len(hazards) + 1
    import datetime
    new_hazard["timestamp"] = datetime.datetime.now().isoformat()
    hazards.append(new_hazard)
    
    # Broadcast update
    await manager.broadcast(json.dumps({"type": "new_hazard", "data": new_hazard}))
    return new_hazard

@app.delete("/hazards/{hazard_id}")
async def delete_hazard(hazard_id: int):
    global hazards
    hazards = [h for h in hazards if h["id"] != hazard_id]
    # Broadcast deletion
    await manager.broadcast(json.dumps({"type": "delete_hazard", "id": hazard_id}))
    return {"status": "deleted", "id": hazard_id}

@app.put("/hazards/{hazard_id}/verify")
async def verify_hazard(hazard_id: int):
    for h in hazards:
        if h["id"] == hazard_id:
            h["verified"] = True
            # Broadcast update - reusing new_hazard type or creating a specific update type
            # Sending 'new_hazard' will upsert in frontend if logic handles ID matching, 
            # otherwise we should send 'update_hazard'. For MVP, let's send 'new_hazard' which contains full data.
            await manager.broadcast(json.dumps({"type": "new_hazard", "data": h}))
            return h
    raise HTTPException(status_code=404, detail="Hazard not found")


@app.post("/auth/login")
def login(creds: AuthLogin):
    if creds.username == "admin" and creds.password == "admin123":
        return {"token": "dummy-admin-token", "role": "authority"}
    return HTTPException(status_code=401, detail="Invalid credentials")

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)
