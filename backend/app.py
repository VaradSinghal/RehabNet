"""
RehabNet – Flask + SocketIO Backend
Serves real-time tremor data, pose analysis, and session metrics
to the Flutter mobile frontend.

ESP32 is simulated via a background thread (ESP32Simulator).
To connect real hardware later:
  - Replace ESP32Simulator with a serial/WebSocket reader
  - Feed parsed packets to tremor_analyzer.add_sample() and emit via socketio
"""

import eventlet
eventlet.monkey_patch()   # Must be first

from flask import Flask, jsonify, request
from flask_socketio import SocketIO, emit
from flask_cors import CORS

from modules.esp32_simulator import ESP32Simulator
from modules.tremor_analyzer  import TremorAnalyzer
from modules.pose_analyzer    import PoseAnalyzer
from modules.session_manager  import SessionManager

# ---------------------------------------------------------------------------
app = Flask(__name__)
app.config["SECRET_KEY"] = "rehabnet-secret-2024"
CORS(app, resources={r"/*": {"origins": "*"}})
socketio = SocketIO(app, cors_allowed_origins="*", async_mode="eventlet")

# Module instances
tremor_analyzer = TremorAnalyzer()
pose_analyzer   = PoseAnalyzer()
session         = SessionManager()

# ---------------------------------------------------------------------------
# ESP32 Simulator – emits to all connected clients
# ---------------------------------------------------------------------------
def _on_esp32_sample(data: dict):
    """Called by ESP32Simulator on every new sample."""
    # Feed into tremor analyser
    tremor_analyzer.add_sample(
        data["accelerometer_x"],
        data["accelerometer_y"],
        data["accelerometer_z"],
    )
    analysis = tremor_analyzer.analyse()

    # Record into session
    session.record_tremor(analysis["severity_score"], analysis["severity_label"])

    payload = {**data, **analysis}
    socketio.emit("tremor_data", payload, namespace="/sensor")


esp32 = ESP32Simulator(emit_callback=_on_esp32_sample, interval_s=0.1)

# ---------------------------------------------------------------------------
# REST Endpoints
# ---------------------------------------------------------------------------
@app.route("/api/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "service": "RehabNet Backend"})


@app.route("/api/session/start", methods=["POST"])
def start_session():
    session.start_session()
    return jsonify({"message": "Session started"})


@app.route("/api/session/stop", methods=["POST"])
def stop_session():
    session.stop_session()
    return jsonify({"message": "Session stopped"})


@app.route("/api/session/metrics", methods=["GET"])
def get_metrics():
    return jsonify(session.get_metrics())


# ---------------------------------------------------------------------------
# Hardware Endpoint (Real ESP32)
# ---------------------------------------------------------------------------
@app.route("/api/sensor/data", methods=["POST"])
def receive_sensor_data():
    """
    Receives JSON payloads from the physical ESP32.
    Expected format: {"accelerometer_x": 0.05, "accelerometer_y": 0.01, "accelerometer_z": 0.98}
    """
    data = request.json
    if not data or "accelerometer_x" not in data:
        return jsonify({"error": "Invalid format"}), 400
        
    # Feed into tremor analyser
    tremor_analyzer.add_sample(
        data["accelerometer_x"],
        data["accelerometer_y"],
        data["accelerometer_z"],
    )
    analysis = tremor_analyzer.analyse()

    # Record into session
    session.record_tremor(analysis["severity_score"], analysis["severity_label"])

    # Broadcast to Flutter via Socket.IO
    payload = {**data, **analysis}
    socketio.emit("tremor_data", payload, namespace="/sensor")
    
    return jsonify({"status": "received"}), 200

# ---------------------------------------------------------------------------
# SocketIO – Pose Analysis Namespace (/pose)
# ---------------------------------------------------------------------------
@socketio.on("landmarks", namespace="/pose")
def handle_landmarks(data):
    """
    Flutter sends: {"landmarks": [...], "exercise": "arm_raise"}
    Server replies with analysis result.
    """
    landmarks = data.get("landmarks", [])
    result = pose_analyzer.analyse_frame(landmarks)

    if result.get("rep_detected"):
        accuracy = result.get("accuracy_pct", 0.0)
        session.record_rep(accuracy)

    emit("pose_result", result)


# ---------------------------------------------------------------------------
# SocketIO – Sensor Namespace (/sensor)
# ---------------------------------------------------------------------------
@socketio.on("connect", namespace="/sensor")
def sensor_connect():
    print("[sensor] client connected")


@socketio.on("disconnect", namespace="/sensor")
def sensor_disconnect():
    print("[sensor] client disconnected")


# ---------------------------------------------------------------------------
# SocketIO – Metrics push (broadcast every second)
# ---------------------------------------------------------------------------
def _push_metrics():
    while True:
        eventlet.sleep(1.0)
        if session.is_active:
            socketio.emit("metrics_update", session.get_metrics(), namespace="/session")


# ---------------------------------------------------------------------------
if __name__ == "__main__":
    # ONLY enable this if you want fake data. Now that we have real hardware, it's disabled.
    # esp32.start()
    # print("ESP32 simulator started")

    socketio.start_background_task(_push_metrics)
    print("Metrics pusher started")

    print("\n-----------------------------------------------------------")
    print("REHAB-NET BACKEND")
    print("Listening for physical ESP32 POST requests on: /api/sensor/data")
    print("Running on http://0.0.0.0:5000")
    print("-----------------------------------------------------------\n")
    
    socketio.run(app, host="0.0.0.0", port=5000, debug=False)
