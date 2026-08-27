import logging
import datetime

# Configure a basic logger that simulates SMS/Email outputs
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - [ALERT SERVICE] - %(levelname)s - %(message)s'
)
logger = logging.getLogger("AlertService")

class AlertService:
    def __init__(self):
        pass

    def send_fraud_alert(self, employee_id: str, organization_id: str, fraud_score: float):
        """
        Simulates sending an SMS or Email alert to a manager regarding high fraud risk.
        """
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        # In a production environment, this would call Twilio API or SendGrid API
        message = (
            f"\n"
            f"===================================================\n"
            f"🚨 CRITICAL ALERT: Timesheet Fraud Detected\n"
            f"===================================================\n"
            f"Organization ID: {organization_id}\n"
            f"Employee ID: {employee_id}\n"
            f"Time: {timestamp}\n"
            f"Risk Score: {fraud_score * 100:.1f}%\n"
            f"Reason: AI detected high probability of buddy punching or location spoofing.\n"
            f"Action Required: Please review the dashboard immediately.\n"
            f"===================================================\n"
        )
        
        logger.warning(message)
        return True

    def send_roster_breach_alert(self, employee_id: str, organization_id: str):
        """
        Simulates sending an alert for a severe roster breach (e.g. unauthorized overtime).
        """
        message = (
            f"⚠️ ROSTER ALERT: Employee {employee_id} clocked in without an authorized shift. "
            f"Please check the live dashboard."
        )
        logger.info(message)
        return True
