#!/usr/bin/env python3
"""
Delling Dashboard - Simple service control panel
"""
import subprocess
from flask import Flask, jsonify, render_template_string

app = Flask(__name__)

# Service definitions
SERVICES = {
    'fm-radio': {
        'name': 'Multi-mode Radio',
        'icon': '📻',
        'service': 'rtl-fm-radio',
        'url': 'http://192.168.4.1:10100',
        'sdr': True,
        'always_on': False,
        'description': None  # Has built-in antenna recommendations
    },
    'dab-radio': {
        'name': 'DAB+ Radio',
        'icon': '📻',
        'service': 'welle-cli',
        'url': 'http://192.168.4.1:7979',
        'sdr': True,
        'always_on': False,
        'description': 'Recommended antenna: 37-75 cm'
    },
    'media': {
        'name': 'Media Server',
        'icon': '🎬',
        'service': 'tinymedia',
        'url': 'http://192.168.4.1:5000',
        'sdr': False,
        'always_on': True
    },
    'kiwix': {
        'name': 'Kiwix',
        'icon': '📚',
        'service': 'kiwix',
        'url': 'http://192.168.4.1:8000',
        'sdr': False,
        'always_on': True
    },
    'ships': {
        'name': 'Ships',
        'icon': '🚢',
        'service': 'aiscatcher',
        'url': 'http://192.168.4.1:8100',
        'sdr': True,
        'always_on': False,
        'description': 'Recommended antenna: 46 cm'
    },
    'meshtastic': {
        'name': 'Meshtastic',
        'icon': '💬',
        'service': None,
        'url': 'http://192.168.4.10',
        'sdr': False,
        'always_on': True
    },
}

SDR_SERVICES = ['rtl-fm-radio', 'welle-cli', 'aiscatcher']

HTML_TEMPLATE = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Delling Hub</title>
    <style>
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            min-height: 100vh;
            padding: 20px;
        }
        h1 {
            color: #fff;
            text-align: center;
            margin-bottom: 24px;
            font-size: 28px;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 16px;
            max-width: 500px;
            margin: 0 auto;
        }
        .btn {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            padding: 24px 16px;
            border: none;
            border-radius: 16px;
            background: linear-gradient(145deg, #2d2d44, #252538);
            color: #fff;
            cursor: pointer;
            transition: all 0.2s ease;
            box-shadow: 0 4px 15px rgba(0,0,0,0.3);
            min-height: 120px;
        }
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(0,0,0,0.4);
        }
        .btn:active {
            transform: translateY(0);
        }
        .btn.loading {
            opacity: 0.7;
            pointer-events: none;
        }
        .btn .icon {
            font-size: 40px;
            margin-bottom: 8px;
        }
        .btn .name {
            font-size: 16px;
            font-weight: 500;
        }
        .btn .status {
            font-size: 11px;
            margin-top: 6px;
            padding: 3px 8px;
            border-radius: 10px;
            background: rgba(255,255,255,0.1);
        }
        .btn .status.running {
            background: rgba(76, 175, 80, 0.3);
            color: #81c784;
        }
        .btn .description {
            font-size: 10px;
            color: #aaa;
            margin-top: 4px;
        }
        .btn.sdr {
            border-left: 3px solid #ff9800;
        }
        .footer {
            text-align: center;
            color: #666;
            margin-top: 24px;
            font-size: 12px;
        }
    </style>
</head>
<body>
    <h1>🌅 Delling Hub</h1>
    <div class="grid">
        {% for key, svc in services.items() %}
        <button class="btn {% if svc.sdr %}sdr{% endif %}" onclick="startService('{{ key }}', '{{ svc.url }}', {{ 'true' if svc.always_on else 'false' }})">
            <span class="icon">{{ svc.icon }}</span>
            <span class="name">{{ svc.name }}</span>
            {% if svc.description %}
            <span class="description">{{ svc.description }}</span>
            {% endif %}
            {% if not svc.always_on %}
            <span class="status" id="status-{{ key }}">-</span>
            {% endif %}
        </button>
        {% endfor %}
    </div>
    <div class="footer">SDR services (orange) share the radio - only one runs at a time</div>

    <script>
        async function startService(key, url, alwaysOn) {
            const btn = event.currentTarget;
            btn.classList.add('loading');
            
            // For always-on services, just open the URL directly
            if (alwaysOn) {
                window.open(url, '_blank');
                btn.classList.remove('loading');
                return;
            }
            
            try {
                const response = await fetch('/api/start/' + key, { method: 'POST' });
                const data = await response.json();
                
                if (data.success) {
                    // Delay to let SDR service fully initialize
                    setTimeout(() => {
                        window.open(url, '_blank');
                    }, 3500);
                }
            } catch (err) {
                console.error('Error:', err);
            }
            
            btn.classList.remove('loading');
            updateStatus();
        }

        async function updateStatus() {
            try {
                const response = await fetch('/api/status');
                const data = await response.json();
                
                for (const [key, running] of Object.entries(data)) {
                    const el = document.getElementById('status-' + key);
                    if (el) {
                        el.textContent = running ? 'running' : 'stopped';
                        el.className = 'status' + (running ? ' running' : '');
                    }
                }
            } catch (err) {
                console.error('Status error:', err);
            }
        }

        // Update status on load and every 5 seconds
        updateStatus();
        setInterval(updateStatus, 5000);
    </script>
</body>
</html>
'''

def run_cmd(cmd):
    """Run a shell command"""
    try:
        subprocess.run(cmd, shell=True, check=False, capture_output=True)
        return True
    except Exception as e:
        print(f"Command error: {e}")
        return False

def stop_sdr_services():
    """Stop all SDR services"""
    for svc in SDR_SERVICES:
        run_cmd(f"sudo systemctl stop {svc}")

def is_service_running(service_name):
    """Check if a systemd service is running"""
    if not service_name:
        return None
    result = subprocess.run(
        f"systemctl is-active {service_name}",
        shell=True, capture_output=True, text=True
    )
    return result.stdout.strip() == "active"

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE, services=SERVICES)

@app.route('/api/start/<service_key>', methods=['POST'])
def start_service(service_key):
    if service_key not in SERVICES:
        return jsonify({'success': False, 'error': 'Unknown service'}), 404
    
    svc = SERVICES[service_key]
    
    # If SDR service, stop others first
    if svc['sdr']:
        stop_sdr_services()
    
    # Start the service if it has one
    if svc['service']:
        run_cmd(f"sudo systemctl start {svc['service']}")
    
    return jsonify({'success': True, 'url': svc['url']})

@app.route('/api/status')
def get_status():
    status = {}
    for key, svc in SERVICES.items():
        # Skip always-on services
        if svc.get('always_on', False):
            continue
        if svc['service']:
            status[key] = is_service_running(svc['service'])
        else:
            status[key] = None
    return jsonify(status)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
