import os
import re
import signal
import subprocess
import time
from flask import Flask, render_template, request, Response, jsonify, send_from_directory
from werkzeug.utils import secure_filename

app = Flask(__name__)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
UPLOAD_FOLDER = os.path.join(BASE_DIR, 'uploads')
CONVERT_FOLDER = os.path.join(BASE_DIR, 'converted')

os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(CONVERT_FOLDER, exist_ok=True)

current_process = None
current_output_file = None


def get_video_duration(filepath):
    try:
        cmd = [
            'ffprobe', '-v', 'error', '-show_entries', 'format=duration',
            '-of', 'default=noprint_wrappers=1:nokey=1', filepath
        ]
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return float(result.stdout.strip())
    except Exception:
        return 0.0


@app.route('/')
def index():
    return render_template('index.html')


@app.route('/convert', methods=['POST'])
def convert():
    global current_process, current_output_file

    file = request.files.get('video')
    if not file or file.filename == '':
        return Response('{"msg": "Error: No file uploaded"}\n', mimetype='application/x-ndjson')

    filename = secure_filename(file.filename)
    unique_id = str(int(time.time()))
    input_filename = f"in_{unique_id}_{filename}"
    output_filename = f"hdr10_{unique_id}_{os.path.splitext(filename)[0]}.mp4"

    input_path = os.path.join(UPLOAD_FOLDER, input_filename)
    output_path = os.path.join(CONVERT_FOLDER, output_filename)
    current_output_file = output_path

    file.save(input_path)
    total_duration = get_video_duration(input_path)

    exp = float(request.form.get('exp', 0.25))
    hl = int(request.form.get('hl', 240))
    sat = float(request.form.get('sat', 1.25))
    speed = request.form.get('speed', 'medium')
    platform = request.form.get('platform', 'none')

    brightness_val = round(exp * 0.15, 3)
    max_fall = int(hl * 0.75)

    # Color grading pipeline: Exposure/Saturation graded before zscale PQ/BT.2020 conversion
    vf_filters = [
        f"eq=brightness={brightness_val}:saturation={sat}",
        "zscale=tin=bt709:t=smpte2084:pin=bt709:p=bt2020:m=bt2020nc",
        "format=yuv420p10le"
    ]

    fps_flag = []
    bitrate_flag = []
    if platform == 'tiktok':
        fps_flag = ['-r', '60']
        bitrate_flag = ['-maxrate', '16M', '-bufsize', '32M']
    elif platform == 'instagram':
        fps_flag = ['-r', '30']
        bitrate_flag = ['-maxrate', '14M', '-bufsize', '28M']

    x265_opts = (
        f"colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:"
        f"master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1):"
        f"max-cll={hl},{max_fall}:hdr10-opt=1:repeat-headers=1"
    )

    cmd = [
        'ffmpeg', '-y', '-i', input_path,
        '-vf', ','.join(vf_filters),
        *fps_flag,
        '-c:v', 'libx265',
        '-preset', speed,
        '-crf', '18',
        *bitrate_flag,
        '-pix_fmt', 'yuv420p10le',
        '-color_primaries', 'bt2020',
        '-color_trc', 'smpte2084',
        '-colorspace', 'bt2020nc',
        '-x265-params', x265_opts,
        '-c:a', 'aac', '-b:a', '256k',
        '-movflags', '+faststart',
        output_path
    ]

    def generate_progress():
        global current_process
        current_process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            universal_newlines=True
        )

        time_pattern = re.compile(r"time=(\d+):(\d+):(\d+\.\d+)")
        fps_pattern = re.compile(r"fps=\s*([\d\.]+)")
        frame_pattern = re.compile(r"frame=\s*(\d+)")

        last_pct = 0
        while True:
            line = current_process.stdout.readline()
            if not line and current_process.poll() is not None:
                break

            if line:
                t_match = time_pattern.search(line)
                fps_match = fps_pattern.search(line)
                frame_match = frame_pattern.search(line)

                cur_fps = fps_match.group(1) if fps_match else "--"
                cur_frames = frame_match.group(1) if frame_match else "--"

                if t_match and total_duration > 0:
                    hours, mins, secs = map(float, t_match.groups())
                    current_secs = hours * 3600 + mins * 60 + secs
                    pct = min(99, int((current_secs / total_duration) * 100))
                    rem_secs = max(0, int((total_duration - current_secs) / (float(cur_fps) if cur_fps != '--' and float(cur_fps) > 0 else 30)))
                    eta_str = f"{rem_secs // 60}:{rem_secs % 60:02d}"

                    if pct > last_pct:
                        last_pct = pct
                        yield f'{{"pct": {pct}, "fps": "{cur_fps}", "frames": "{cur_frames}", "eta": "{eta_str}", "msg": "Encoding HDR10 BT.2020 / PQ frames..."}}\n'

        ret = current_process.poll()
        if ret == 0:
            yield f'{{"pct": 100, "fps": "--", "frames": "{cur_frames}", "eta": "Done", "download_url": "/download/{output_filename}"}}\n'
        else:
            yield '{"msg": "Process interrupted or stopped."}\n'

        if os.path.exists(input_path):
            try:
                os.remove(input_path)
            except OSError:
                pass

    return Response(generate_progress(), mimetype='application/x-ndjson')


@app.route('/pause', methods=['POST'])
def pause_process():
    global current_process
    if current_process and current_process.poll() is None:
        try:
            current_process.send_signal(signal.SIGSTOP)
            return jsonify({'status': 'paused'})
        except Exception as e:
            return jsonify({'error': str(e)}), 500
    return jsonify({'error': 'No active process'}), 400


@app.route('/resume', methods=['POST'])
def resume_process():
    global current_process
    if current_process and current_process.poll() is None:
        try:
            current_process.send_signal(signal.SIGCONT)
            return jsonify({'status': 'resumed'})
        except Exception as e:
            return jsonify({'error': str(e)}), 500
    return jsonify({'error': 'No active process'}), 400


@app.route('/stop', methods=['POST'])
def stop_process():
    global current_process, current_output_file
    if current_process and current_process.poll() is None:
        try:
            current_process.kill()
            current_process = None
            if current_output_file and os.path.exists(current_output_file):
                os.remove(current_output_file)
            return jsonify({'status': 'stopped'})
        except Exception as e:
            return jsonify({'error': str(e)}), 500
    return jsonify({'status': 'idle'})


@app.route('/download/<filename>')
def download_file(filename):
    return send_from_directory(CONVERT_FOLDER, filename, as_attachment=True)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)
