import google.generativeai as genai
import os
import json

class AgentParser:
    def __init__(self):
        # We need an API key to parse natural language to JSON.
        api_key = os.environ.get("GEMINI_API_KEY")
        if api_key:
            genai.configure(api_key=api_key)
            self.model = genai.GenerativeModel('gemini-2.5-flash')
        else:
            self.model = None

    def parse_command(self, prompt: str) -> dict:
        """
        Parses a natural language prompt from the user into a structured JSON action
        that the Flutter app can execute.
        """
        if not self.model:
            print("WARNING: No GEMINI_API_KEY found, returning fallback action.")
            return {"action": "error", "message": "Gemini API key not configured in backend."}
            
        system_prompt = """
        You are an AI assistant built into the 'Vigil' workforce management app.
        Your job is to read the user's natural language command and convert it into a structured JSON object.
        
        Available Actions:
        1. toggle_theme: Used when the user wants to switch to light mode or dark mode. 
           Payload should be "light" or "dark".
           Example: {"action": "toggle_theme", "payload": "dark"}
           
        2. navigate: Used when the user wants to go to a specific page.
           Valid paths: "/dashboard", "/rosters", "/staff", "/leave", "/reports", "/settings"
           Example: {"action": "navigate", "payload": "/rosters"}
           
        3. chat: Used when the user is just asking a question or making small talk, rather than commanding the UI.
           Payload is your response.
           Example: {"action": "chat", "payload": "I am the Vigil AI. How can I assist you today?"}
           
        Respond ONLY with the JSON object. Do not wrap it in markdown block quotes like ```json.
        """
        
        try:
            response = self.model.generate_content(system_prompt + "\n\nUser Command: " + prompt)
            text = response.text.strip()
            if text.startswith("```json"):
                text = text[7:-3]
            elif text.startswith("```"):
                text = text[3:-3]
                
            return json.loads(text)
        except Exception as e:
            return {"action": "error", "payload": f"Failed to parse command: {str(e)}"}
