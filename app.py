from flask import Flask, request, render_template_string
import subprocess
import os

app = Flask(__name__)
UPLOAD_FOLDER = 'uploads'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

HTML = '''
<!doctype html>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body { font-family: sans-serif; padding: 20px; }
  button, input { margin-top: 10px; display: block; }
</style>
<h2>SDR to HDR10 Converter</h2>
<form method="post" enctype="multipart/form-data">
  <input type="file" name="video" required>
  <button type="submit">Convert Video</button>
</form>
<pre>{{ output }}</pre>
'''

@app.route('/', methods=['GET', 'POST'])
def upload_file():
    output = ""
    if request.method == 'POST':
        file = request.files.get('video')
        if file:
            filepath = os.path.join(UPLOAD_FOLDER, file.filename)
            file.save(filepath)
            result = subprocess.run(['bash', 'sdr2hdr.sh', filepath], capture_output=True, text=True)
            output = result.stdout or result.stderr
    return render_template_string(HTML, output=output)

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000, debug=False)
