import xgboost as xgb
import pandas as pd

class FraudClassifier:
    def __init__(self):
        # XGBoost classifier to score buddy punching and spoofing risk
        self.model = xgb.XGBClassifier(use_label_encoder=False, eval_metric='logloss')
        self.is_trained = False

    def train(self, X_train: pd.DataFrame, y_train: pd.Series):
        """
        Train the classifier on engineered features.
        y_train = 1 (fraud), 0 (normal)
        """
        if len(X_train) > 0:
            self.model.fit(X_train, y_train)
            self.is_trained = True

    def calculate_fraud_risk(self, features: list) -> float:
        """
        Returns a risk score between 0.0 and 1.0.
        Features expected: 
        [geofence_distance, device_fingerprint_mismatch, rapid_successive_checkins]
        """
        if not self.is_trained:
            # Prototype fallback: simple heuristic
            geofence_dist, device_mismatch, rapid_checkin = features
            risk = 0.0
            if geofence_dist > 500: # more than 500 meters away
                risk += 0.4
            if device_mismatch == 1:
                risk += 0.4
            if rapid_checkin == 1:
                risk += 0.2
            return min(risk, 1.0)
            
        probability = self.model.predict_proba([features])[0][1]
        return float(probability)
