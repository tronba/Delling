#!/usr/bin/env python3
"""
Delling Map Viewer — Offline maps with AIS ship tracking overlay

Serves:
  • Map tiles from MBTiles files on USB drive (/maps folder)
  • Leaflet-based map viewer with ship overlay
  • AIS ship data proxy from AIS-catcher

Port: 8082
"""

import os
import glob
import sqlite3
from flask import Flask, Response, jsonify, send_from_directory
import urllib.request

APP_DIR = os.path.dirname(os.path.abspath(__file__))
app = Flask(__name__, static_folder='static')

# ─── Configuration ───────────────────────────────────────────────────────
AIS_URL = os.environ.get('AIS_URL', 'http://127.0.0.1:8100')
USB_MOUNT = os.environ.get('USB_MOUNT', '/media/usb')


# ─── USB / MBTiles Discovery ────────────────────────────────────────────

def _find_maps_dir():
    """Locate the maps folder on USB (case-insensitive search).

    Checks /media/usb and /media/<user>/usb for a folder named
    maps, Maps, or MAPS.
    """
    search_bases = [USB_MOUNT]
    user = os.environ.get('USER', '')
    if user:
        user_path = '/media/{}/usb'.format(user)
        if user_path != USB_MOUNT:
            search_bases.append(user_path)

    for base in search_bases:
        if not os.path.isdir(base):
            continue
        try:
            for entry in os.listdir(base):
                if entry.lower() == 'maps' and os.path.isdir(os.path.join(base, entry)):
                    return os.path.join(base, entry)
        except OSError:
            continue
    return None


def _find_mbtiles():
    """Return {name: filepath} of available .mbtiles files."""
    maps_dir = _find_maps_dir()
    if not maps_dir:
        return {}
    result = {}
    for f in sorted(glob.glob(os.path.join(maps_dir, '*.mbtiles'))):
        name = os.path.splitext(os.path.basename(f))[0]
        result[name] = f
    return result


# ─── MBTiles Tile Reading ───────────────────────────────────────────────

def _read_tile(mbtiles_path, z, x, y):
    """Read a single tile from an MBTiles (SQLite) file.

    MBTiles uses TMS y-coordinate which is flipped compared to
    the XYZ/Slippy Map convention used by Leaflet.
    """
    tms_y = (2 ** z - 1) - y
    try:
        conn = sqlite3.connect('file:{}?mode=ro'.format(mbtiles_path), uri=True)
        cur = conn.execute(
            'SELECT tile_data FROM tiles '
            'WHERE zoom_level=? AND tile_column=? AND tile_row=?',
            (z, x, tms_y)
        )
        row = cur.fetchone()
        conn.close()
        return row[0] if row else None
    except Exception:
        return None


def _read_metadata(mbtiles_path):
    """Read the metadata table from an MBTiles file."""
    try:
        conn = sqlite3.connect('file:{}?mode=ro'.format(mbtiles_path), uri=True)
        cur = conn.execute('SELECT name, value FROM metadata')
        meta = dict(cur.fetchall())
        conn.close()
        return meta
    except Exception:
        return {}


# ─── Routes ──────────────────────────────────────────────────────────────

@app.route('/')
def index():
    """Serve the map viewer page."""
    return send_from_directory(APP_DIR, 'index.html')


@app.route('/api/tilesets')
def api_tilesets():
    """List available MBTiles tilesets with metadata."""
    tilesets = _find_mbtiles()
    result = []
    for name, path in tilesets.items():
        meta = _read_metadata(path)
        result.append({
            'name': name,
            'format': meta.get('format', 'png'),
            'description': meta.get('description', name),
            'bounds': meta.get('bounds', ''),
            'center': meta.get('center', ''),
            'minzoom': int(meta.get('minzoom', 0)),
            'maxzoom': int(meta.get('maxzoom', 18)),
        })
    return jsonify(result)


@app.route('/tiles/<tileset>/<int:z>/<int:x>/<int:y>')
def serve_tile(tileset, z, x, y):
    """Serve a single map tile from MBTiles."""
    tilesets = _find_mbtiles()
    if tileset not in tilesets:
        return Response('Tileset not found', status=404)

    tile_data = _read_tile(tilesets[tileset], z, x, y)
    if tile_data is None:
        return Response(b'', status=204)

    meta = _read_metadata(tilesets[tileset])
    fmt = meta.get('format', 'png')
    content_types = {
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'webp': 'image/webp',
        'pbf': 'application/x-protobuf',
    }
    ct = content_types.get(fmt, 'application/octet-stream')

    headers = {
        'Cache-Control': 'public, max-age=86400',
        'Access-Control-Allow-Origin': '*',
    }
    if fmt == 'pbf':
        headers['Content-Encoding'] = 'gzip'

    return Response(tile_data, content_type=ct, headers=headers)


@app.route('/api/ships')
def api_ships():
    """Proxy AIS ship data from AIS-catcher.

    Returns an empty list if AIS-catcher is not running.
    """
    try:
        req = urllib.request.urlopen('{}/api/ships'.format(AIS_URL), timeout=2)
        data = req.read()
        return Response(data, content_type='application/json',
                        headers={'Cache-Control': 'no-cache',
                                 'Access-Control-Allow-Origin': '*'})
    except Exception:
        return jsonify([])


# ─── Main ────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8082, debug=False)
