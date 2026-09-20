import json
import os
import re
import subprocess
import threading
from flask import Flask, jsonify, render_template, request

app = Flask(__name__)

# Global state tracker
ENCODER_STATE = {
    "is_running": False,
    "current_frame": 0,
    "total_frames": 0,
    "remaining_frames": 0,
    "fps": 0.0,
    "eta": "--:--",
    "percentage": 0,
    "status": "Idle",
    "process": None,
}


def get_exact_video_metadata(filepath):
  """Probe video stream packet-by-packet to find the exact frame count

  and avoid variable frame rate estimation issues.
  """
  cmd = [
      "ffprobe",
      "-v",
      "error",
      "-select_streams",
      "v:0",
      "-count_packets",
      "-show_entries",
      "stream=nb_read_packets,r_frame_rate,duration",
      "-of",
      "json",
      filepath,
  ]
  try:
    proc = subprocess.run(cmd, capture_output=True, text=True, check=True)
    stream_info = json.loads(proc.stdout)["streams"][0]

    packets = stream_info.get("nb_read_packets")
    if packets and packets != "N/A":
      return int(packets)

    # Fallback to duration * fps if packet counting fails
    num, den = map(float, stream_info["r_frame_rate"].split("/"))
    fps = num / den
    duration = float(stream_info.get("duration", 0))
    return max(1, int(round(duration * fps)))
  except Exception as err:
    print(f"ffprobe error: {err}")
    return 1


def run_ffmpeg_worker(input_path, output_path, exposure, max_cll, saturation):
  global ENCODER_STATE

  ENCODER_STATE["status"] = "Analyzing stream and staging pipeline..."
  total_frames = get_exact_video_metadata(input_path)

  ENCODER_STATE["total_frames"] = total_frames
  ENCODER_STATE["remaining_frames"] = total_frames
  ENCODER_STATE["current_frame"] = 0
  ENCODER_STATE["fps"] = 0.0
  ENCODER_STATE["eta"] = "--:--"
  ENCODER_STATE["percentage"] = 0
  ENCODER_STATE["status"] = "Encoding HDR10 BT.2020 / PQ frames..."

  # libx265 HDR10 Pipeline filtergraph
  # Exposure/Saturation adjustment + Rec.709 to BT.2020 PQ color space matrices
  vf_filter = (
      f"eq=brightness={exposure}:saturation={saturation},"
      "zscale=tin=bt709:t=smpte2084:m=bt2020nc:min=bt2020nc:pin=bt709:p=bt2020,"
      "format=yuv420p10le"
  )

  x265_params = (
      "hdr10-opt=1:repeat-headers=1:colorprim=bt2020:transfer=smpte2084:"
      f"colormatrix=bt2020nc:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1):"
      f"max-cll={max_cll},100"
  )

  cmd = [
      "ffmpeg",
      "-y",
      "-i",
      input_path,
      "-vf",
      vf_filter,
      "-c:v",
      "libx265",
      "-preset",
      "ultrafast",
      "-x265-params",
      x265_params,
      "-c:a",
      "copy",
      "-progress",
      "pipe:1",
      output_path,
  ]

  proc = subprocess.Popen(
      cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, universal_newlines=True
  )
  ENCODER_STATE["process"] = proc

  for line in proc.stdout:
    line = line.strip()
    if line.startswith("frame="):
      curr = int(line.split("=")[1].strip())
      ENCODER_STATE["current_frame"] = curr
      ENCODER_STATE["remaining_frames"] = max(0, total_frames - curr)
      ENCODER_STATE["percentage"] = min(
          100, int(round((curr / total_frames) * 100))
      )
    elif line.startswith("fps="):
      try:
        cur_fps = float(line.split("=")[1].strip())
        ENCODER_STATE["fps"] = cur_fps

        rem = ENCODER_STATE["remaining_frames"]
        if cur_fps > 0 and rem > 0:
          eta_sec = int(rem / cur_fps)
          m, s = divmod(eta_sec, 60)
          h, m = divmod(m, 60)
          ENCODER_STATE["eta"] = (
              f"{h}:{m:02d}:{s:02d}" if h > 0 else f"{m:02d}:{s:02d}"
          )
        elif rem == 0 and total_frames > 0:
          ENCODER_STATE["eta"] = "00:00"
        else:
          ENCODER_STATE["eta"] = "--:--"
      except ValueError:
        pass

  proc.wait()
  ENCODER_STATE["is_running"] = False
  ENCODER_STATE["status"] = "Completed"
  ENCODER_STATE["eta"] = "00:00"


@app.route("/")
def index():
  return render_template("index.html")


@app.route("/start", methods=["POST"])
def start_encoding():
  global ENCODER_STATE
  if ENCODER_STATE["is_running"]:
    return jsonify({"error": "Encoder already running"}), 400

  data = request.json or {}
  input_file = data.get("input_file", "input.mp4")
  output_file = data.get("output_file", "output_hdr10.mp4")
  exposure = float(data.get("exposure", 0.0))
  max_cll = int(data.get("max_cll", 240))
  saturation = float(data.get("saturation", 1.0))

  ENCODER_STATE["is_running"] = True
  t = threading.Thread(
      target=run_ffmpeg_worker,
      args=(input_file, output_file, exposure, max_cll, saturation),
  )
  t.daemon = True
  t.start()

  return jsonify({"status": "Started"})


@app.route("/stop", methods=["POST"])
def stop_encoding():
  global ENCODER_STATE
  if ENCODER_STATE["process"]:
    ENCODER_STATE["process"].terminate()
    ENCODER_STATE["is_running"] = False
    ENCODER_STATE["status"] = "Aborted by user"
  return jsonify({"status": "Stopped"})


@app.route("/status")
def get_status():
  return jsonify({
      "is_running": ENCODER_STATE["is_running"],
      "fps": f"{ENCODER_STATE['fps']:.1f}",
      "frames_display": f"{ENCODER_STATE['remaining_frames']} / {ENCODER_STATE['total_frames']}",
      "remaining_frames": ENCODER_STATE["remaining_frames"],
      "total_frames": ENCODER_STATE["total_frames"],
      "current_frame": ENCODER_STATE["current_frame"],
      "eta": ENCODER_STATE["eta"],
      "percentage": ENCODER_STATE["percentage"],
      "status": ENCODER_STATE["status"],
  })


if __name__ == "__main__":
  app.run(host="0.0.0.0", port=5000, debug=False)
                 
