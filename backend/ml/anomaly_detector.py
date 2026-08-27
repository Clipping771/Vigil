import pandas as pd
from sklearn.ensemble import IsolationForest

class AnomalyDetector:
    def __init__(self):
        # Isolation Forest is an unsupervised model perfect for detecting outliers
        # (e.g. unusual check-in times or durations)
        self.model = IsolationForest(n_estimators=100, contamination=0.05, random_state=42)
        self.is_trained = False

    def train(self, historical_data: pd.DataFrame):
        """
        Train the isolation forest on historical clock events.
        Expected features: hour_of_day, day_of_week, shift_duration, geo_distance_from_site
        """
        if len(historical_data) > 10:
            self.model.fit(historical_data)
            self.is_trained = True

    def detect_anomaly(self, event_features: list) -> bool:
        """
        Returns True if the event is considered an anomaly
        event_features format: [hour_of_day, day_of_week, shift_duration, geo_distance_from_site]
        """
        if not self.is_trained:
            # Fallback for prototype without enough data
            hour = event_features[0]
            # Simple rule fallback if not trained: check-in between 1am and 4am is suspicious
            if 1 <= hour <= 4:
                return True
            return False
            
        prediction = self.model.predict([event_features])
        # -1 means anomaly, 1 means normal in sklearn's IsolationForest
        return prediction[0] == -1
