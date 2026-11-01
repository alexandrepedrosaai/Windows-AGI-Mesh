import json
import requests

def sendinferenceto_mesh(value):
    payload = {"signal": value}
    response = requests.post("https://your-mesh-endpoint/api/inference", json=payload)
    return response.json()

def copilotagenthandler(event):
    input_value = event.get("input", 1.0)
    result = sendinferencetomesh(inputvalue)
    return {"mesh_output": result}
