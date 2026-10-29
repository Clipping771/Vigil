"""Vigil AI engine.

Every endpoint (except the health check) requires the caller's Supabase access
token in `Authorization: Bearer <token>`. The token is verified with Supabase
Auth and resolved to an employee, and all reads/writes are scoped to that
employee's organization — the service-role key never acts on client-supplied
organization IDs.
"""

import datetime
import logging
import math
import os
from typing import Optional

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException, Header
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from supabase import Client, create_client

from ml.agent_parser import AgentParser
from ml.anomaly_detector import AnomalyDetector
from ml.fraud_classifier import FraudClassifier
from ml.llm_reporter import LLMReporter
from notifications.alert_service import AlertService

load_dotenv()
logger = logging.getLogger("vigil")

app = FastAPI(title="Vigil AI Engine", version="1.0.0")

allowed_origins = [o.strip() for o in os.environ.get("ALLOWED_ORIGINS", "").split(",") if o.strip()]
if allowed_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=allowed_origins,
        allow_methods=["GET", "POST"],
        allow_headers=["Authorization", "Content-Type"],
    )

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or os.environ.get("SUPABASE_KEY", "")
supabase: Optional[Client] = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY) if SUPABASE_URL and SUPABASE_SERVICE_KEY else None

anomaly_detector = AnomalyDetector()
fraud_classifier = FraudClassifier()
llm_reporter = LLMReporter()
agent_parser = AgentParser()
alert_service = AlertService()

MANAGER_ROLES = {"owner", "admin", "system_admin", "manager", "hr"}


class Caller(BaseModel):
    employee_id: str
    organization_id: str
    role: str


def db() -> Client:
    if supabase is None:
        raise HTTPException(status_code=503, detail="Backend is not configured")
    return supabase


def current_caller(authorization: str = Header(default="")) -> Caller:
    if not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.split(" ", 1)[1].strip()
    client = db()
    try:
        user = client.auth.get_user(token).user
    except Exception:
        user = None
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid or expired token")

    rows = (
        client.table("employees")
        .select("id, organization_id, role")
        .eq("auth_user_id", user.id)
        .limit(1)
        .execute()
        .data
    )
    if not rows:
        raise HTTPException(status_code=403, detail="No employee profile for this account")
    row = rows[0]
    return Caller(employee_id=row["id"], organization_id=row["organization_id"], role=row["role"])


def require_manager(caller: Caller = Depends(current_caller)) -> Caller:
    if caller.role not in MANAGER_ROLES:
        raise HTTPException(status_code=403, detail="Manager access required")
    return caller


def _haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6_371_000
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = math.radians(lat2 - lat1), math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


class IngestRequest(BaseModel):
    event_id: str = Field(..., min_length=1)


class AgentCommand(BaseModel):
    prompt: str = Field(..., min_length=1, max_length=2000)


@app.get("/")
def health():
    return {"status": "ok", "configured": supabase is not None}


@app.post("/ingest")
def ingest_event(body: IngestRequest, caller: Caller = Depends(current_caller)):
    """Scores a stored clock event for anomalies and fraud risk."""
    client = db()
    rows = client.table("clock_events").select("*").eq("id", body.event_id).limit(1).execute().data
    if not rows:
        raise HTTPException(status_code=404, detail="Event not found")
    event = rows[0]
    if event["organization_id"] != caller.organization_id:
        raise HTTPException(status_code=404, detail="Event not found")
    if caller.role not in MANAGER_ROLES and event["employee_id"] != caller.employee_id:
        raise HTTPException(status_code=403, detail="Not your event")

    event_time = datetime.datetime.fromisoformat(event["event_time"].replace("Z", "+00:00"))

    # Distance from the nearest authorised site (0 when location is unknown).
    distance_m = 0.0
    if event.get("latitude") is not None and event.get("longitude") is not None:
        zones = (
            client.table("geofence_zones")
            .select("latitude, longitude, radius_meters")
            .eq("organization_id", caller.organization_id)
            .execute()
            .data
        )
        if zones:
            distance_m = min(
                max(0.0, _haversine_m(event["latitude"], event["longitude"], z["latitude"], z["longitude"]) - z["radius_meters"])
                for z in zones
            )

    # Rapid successive punches by the same employee (possible buddy punching).
    window_start = (event_time - datetime.timedelta(minutes=2)).isoformat()
    recent = (
        client.table("clock_events")
        .select("id")
        .eq("employee_id", event["employee_id"])
        .eq("event_type", event["event_type"])
        .gte("event_time", window_start)
        .lte("event_time", event["event_time"])
        .neq("id", event["id"])
        .execute()
        .data
    )
    rapid = 1 if recent else 0

    is_anomaly = anomaly_detector.detect_anomaly([event_time.hour, event_time.weekday(), 0, distance_m])
    fraud_score = fraud_classifier.calculate_fraud_risk([distance_m, 0, rapid])

    exceptions = []
    if is_anomaly:
        exceptions.append({
            "exception_type": "statistical_anomaly",
            "severity": "medium",
            "description": f"Unusual punch time or location ({event_time:%H:%M} UTC, {distance_m:.0f} m from nearest site).",
        })
    if fraud_score > 0.5:
        exceptions.append({
            "exception_type": "fraud_risk",
            "severity": "critical" if fraud_score > 0.8 else "high",
            "description": f"Elevated fraud risk (score {fraud_score:.2f}).",
        })
        if fraud_score > 0.8:
            alert_service.send_fraud_alert(event["employee_id"], caller.organization_id, fraud_score)

    for ex in exceptions:
        client.table("exception_records").insert({
            **ex,
            "organization_id": caller.organization_id,
            "employee_id": event["employee_id"],
            "status": "pending",
        }).execute()

    return {"event_id": event["id"], "anomaly": is_anomaly, "fraud_score": fraud_score, "exceptions_raised": len(exceptions)}


@app.post("/generate_report")
def generate_weekly_report(caller: Caller = Depends(require_manager)):
    """LLM summary of the caller's organization's exceptions from the last 7 days."""
    since = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=7)).isoformat()
    exceptions = (
        db().table("exception_records")
        .select("exception_type, severity, status, description, created_at")
        .eq("organization_id", caller.organization_id)
        .gte("created_at", since)
        .order("created_at", desc=True)
        .limit(200)
        .execute()
        .data
    )
    return {"status": "success", "report": llm_reporter.generate_weekly_summary(exceptions)}


@app.post("/api/agent")
def process_agent_command(command: AgentCommand, caller: Caller = Depends(current_caller)):
    """Parses a natural-language command into a structured app action."""
    return {"status": "success", "data": agent_parser.parse_command(command.prompt)}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8000")))
