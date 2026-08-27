from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional, List
import datetime
import os
from supabase import create_client, Client
from dotenv import load_dotenv

from ml.anomaly_detector import AnomalyDetector
from ml.fraud_classifier import FraudClassifier
from ml.forecaster import Forecaster
from ml.llm_reporter import LLMReporter
from ml.agent_parser import AgentParser
from notifications.alert_service import AlertService

load_dotenv()

app = FastAPI(title="Vigil AI Engine")

# Supabase Initialization
url: str = os.environ.get("SUPABASE_URL", "")
key: str = os.environ.get("SUPABASE_KEY", "")

# We only initialize if keys are present (useful for tests)
supabase: Optional[Client] = create_client(url, key) if url and key else None

# Initialize ML Modules
anomaly_detector = AnomalyDetector()
fraud_classifier = FraudClassifier()
forecaster = Forecaster()
llm_reporter = LLMReporter()
agent_parser = AgentParser()
alert_service = AlertService()

class ClockEvent(BaseModel):
    id: str
    employee_id: str
    organization_id: str
    event_type: str
    event_time: str

class ExceptionRecord(BaseModel):
    organization_id: str
    employee_id: str
    exception_type: str
    severity: str
    status: str
    description: str

class AgentCommand(BaseModel):
    prompt: str

@app.get("/")
def read_root():
    return {"status": "Vigil AI Engine is running"}

@app.post("/ingest")
async def ingest_event(event: ClockEvent):
    """
    Endpoint for receiving clock events and running AI/ML anomaly detection.
    """
    # 1. Run Anomaly Detection (Isolation Forest)
    is_anomaly = anomaly_detector.detect_anomaly([2, 1, 0, 0]) # Mock features: hour 2am
    
    # 2. Run Fraud Detection (XGBoost)
    fraud_score = fraud_classifier.calculate_fraud_risk([600, 1, 0]) # Mock features: 600m away, device mismatch
    
    # 3. Insert exception to Supabase if flagged
    exceptions = []
    if is_anomaly:
        exceptions.append({
            "organization_id": event.organization_id,
            "employee_id": event.employee_id,
            "exception_type": "statistical_anomaly",
            "severity": "high",
            "status": "pending",
            "description": "Unusual clock event time/location detected by AI.",
            "created_at": datetime.datetime.now().isoformat()
        })
        
    if fraud_score > 0.5:
         exceptions.append({
            "organization_id": event.organization_id,
            "employee_id": event.employee_id,
            "exception_type": "fraud_risk",
            "severity": "critical",
            "status": "pending",
            "description": f"High fraud risk detected (score: {fraud_score:.2f})",
            "created_at": datetime.datetime.now().isoformat()
        })
         
         # Trigger real-time alert for critical fraud
         if fraud_score > 0.8:
             alert_service.send_fraud_alert(event.employee_id, event.organization_id, fraud_score)
        
    if supabase and exceptions:
        for ex in exceptions:
            supabase.table("exception_records").insert(ex).execute()
    
    return {"status": "success", "event_processed": event.id, "anomaly": is_anomaly, "fraud_score": fraud_score}

@app.post("/generate_report")
async def generate_weekly_report(organization_id: str):
    """
    Endpoint to trigger LLM-based weekly report generation for an organization.
    """
    if not supabase:
        return {"status": "error", "message": "Supabase not configured"}
        
    # Fetch recent exceptions for this org
    response = supabase.table("exception_records").select("*").eq("organization_id", organization_id).limit(20).execute()
    exceptions = response.data
    
    report = llm_reporter.generate_weekly_summary(exceptions)
    return {"status": "success", "report": report}

@app.post("/api/agent")
async def process_agent_command(command: AgentCommand):
    """
    Endpoint for natural language agent commands (e.g. "turn on dark mode").
    """
    result = agent_parser.parse_command(command.prompt)
    return {"status": "success", "data": result}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
