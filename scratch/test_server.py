import requests
import json

url = "http://localhost:5000/feedback"
data = {
    "context": "ABC",
    "actual": "A",
    "predicted": "B",
    "correct": False
}

try:
    response = requests.post(url, json=data)
    print(f"Status Code: {response.status_code}")
    print(f"Response: {response.json()}")
except Exception as e:
    print(f"Error: {e}")
