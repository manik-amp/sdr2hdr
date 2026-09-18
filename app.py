from flask import Flask, request, render_template_string
import subprocess
import os

app = Flask(__name__)
UPLOAD_FOLDER = 'uploads'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

HTML = '''
<!doctype html>
<h2>SDR to HDR Converter</h2>
<form method=post enctype=multipart/form-data>
  <input type=file name=video required>
  <input type=submit value="Convert">
</form>
<pre>{{ output }}</pre>
'''

@app.route('/', methods=['GET', 'POST'])
def upload_file():
    output = ""
    if request.method == 'POST':
        file = request.files['video']
        if file:
            filepath = os.path.join(UPLOAD_FOLDER, file.filename)
            file.save(filepath)
            # Run the bash script against the uploaded video
            result = subprocess.run(['bash', 'sdr2hdr.sh', filepath], capture_output=True, text=True)
            output = result.stdout or result.stderr
    return render_template_string(HTML, output=output)

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000, debug=True)
