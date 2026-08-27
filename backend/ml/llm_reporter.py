import os
import google.generativeai as genai
from typing import List, Dict

class LLMReporter:
    def __init__(self):
        api_key = os.environ.get("GEMINI_API_KEY", "")
        if api_key:
            genai.configure(api_key=api_key)
            self.model = genai.GenerativeModel('gemini-1.5-pro-latest')
            self.is_ready = True
        else:
            self.is_ready = False

    def generate_weekly_summary(self, exceptions: List[Dict]) -> str:
        """
        Converts structured exception data into plain-English weekly summaries.
        """
        if not self.is_ready:
            return "Automated Natural-Language Summary is unavailable. Please set GEMINI_API_KEY."

        prompt = f"""
        You are an AI HR Assistant. Summarize the following attendance exceptions for the week.
        Highlight severe issues (e.g., fraud, roster breaches) and recommend actions for managers.
        Keep it professional and concise.

        Exceptions Data:
        {exceptions}
        """

        try:
            response = self.model.generate_content(prompt)
            return response.text
        except Exception as e:
            return f"Error generating report: {e}"
