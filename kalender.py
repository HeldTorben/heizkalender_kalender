from flask import Flask, request, jsonify, send_from_directory
from icalendar import Calendar, Event
from datetime import datetime
import uuid
import os
import json

app = Flask(__name__)
ICS_PATH = "/var/www/kalender/heizung.ics"
ROOMS_PATH = "/var/www/kalender/rooms.json"

# ===== Kalender =====
def load_cal():
    if os.path.exists(ICS_PATH):
        with open(ICS_PATH, "rb") as f:
            return Calendar.from_ical(f.read())
    cal = Calendar()
    cal.add("version", "2.0")
    cal.add("prodid", "-//Heizkalender//DE")
    return cal

def save_cal(cal):
    with open(ICS_PATH, "wb") as f:
        f.write(cal.to_ical())

# ===== Räume =====
def load_rooms():
    if os.path.exists(ROOMS_PATH):
        with open(ROOMS_PATH, "r") as f:
            return json.load(f)
    return []

def save_rooms(rooms):
    with open(ROOMS_PATH, "w") as f:
        json.dump(rooms, f)

# ===== Routes =====
@app.route("/")
def index():
    return send_from_directory("/var/www/kalender", "index.html")

@app.route("/rooms", methods=["GET"])
def get_rooms():
    return jsonify(load_rooms())

@app.route("/rooms", methods=["POST"])
def add_room():
    data = request.json
    rooms = load_rooms()
    if any(r["resource"] == data["resource"] for r in rooms):
        return jsonify({"error": "Ressourcenname bereits vorhanden"}), 400
    rooms.append({"name": data["name"], "resource": data["resource"]})
    save_rooms(rooms)
    return jsonify({"status": "ok"})

@app.route("/rooms/<resource>", methods=["DELETE"])
def delete_room(resource):
    rooms = load_rooms()
    rooms = [r for r in rooms if r["resource"] != resource]
    save_rooms(rooms)
    return jsonify({"status": "ok"})

@app.route("/events", methods=["GET"])
def get_events():
    cal = load_cal()
    events = []
    for component in cal.walk():
        if component.name == "VEVENT":
            events.append({
                "id": str(component.get("uid")),
                "title": str(component.get("summary")),
                "start": component.get("dtstart").dt.isoformat(),
                "end": component.get("dtend").dt.isoformat(),
                "description": str(component.get("description", ""))
            })
    return jsonify(events)

@app.route("/events", methods=["POST"])
def add_event():
    data = request.json
    cal = load_cal()
    event = Event()
    event.add("uid", str(uuid.uuid4()))
    event.add("summary", data["title"])
    event.add("dtstart", datetime.fromisoformat(data["start"]))
    event.add("dtend", datetime.fromisoformat(data["end"]))
    event.add("description", data.get("description", ""))
    cal.add_component(event)
    save_cal(cal)
    return jsonify({"status": "ok"})

@app.route("/events/<uid>", methods=["DELETE"])
def delete_event(uid):
    cal = load_cal()
    new_cal = Calendar()
    for key, value in cal.items():
        new_cal.add(key, value)
    for component in cal.walk():
        if component.name == "VEVENT" and str(component.get("uid")) != uid:
            new_cal.add_component(component)
    save_cal(new_cal)
    return jsonify({"status": "ok"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
