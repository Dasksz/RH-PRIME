import json
import os
from pathlib import Path

DATA = Path(os.environ.get('LOCALAPPDATA', Path.home() / '.local' / 'share')) / 'RHPrime'
DATA.mkdir(parents=True, exist_ok=True)
CONFIG = DATA / 'config.json'
DEFAULTS = {
 'supabase_url': 'https://gcksbfstheavpfgcdndb.supabase.co',
 'web_url': 'https://dasksz.github.io/RH-PRIME/',
 'n8n_url': 'http://127.0.0.1:5679/webhook/holerites-rh-prime-v2',
 'signature_url': '', 'signature_environment': 'sandbox',
 'google_client_file': str(DATA / 'credenciais_drive.json'),
 'work_dir': str(DATA / 'lotes'), 'tesseract_path': '',
 'allow_background': False, 'start_with_windows': False,
}

def load_config():
    return {**DEFAULTS, **(json.loads(CONFIG.read_text('utf-8')) if CONFIG.exists() else {})}

def save_config(config):
    temp = CONFIG.with_suffix('.tmp')
    temp.write_text(json.dumps(config, ensure_ascii=False, indent=2), 'utf-8')
    temp.replace(CONFIG)

def get_secret(name):
    import keyring
    return keyring.get_password('RH PRIME', name)

def set_secret(name, value):
    import keyring
    if value:
        keyring.set_password('RH PRIME', name, value)
    elif keyring.get_password('RH PRIME', name):
        keyring.delete_password('RH PRIME', name)

PUBLIC_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdja3NiZnN0aGVhdnBmZ2NkbmRiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc3NTA3MjcsImV4cCI6MjA5MzMyNjcyN30.5yqzDt5mTJRpTavKq4GJ0CwX6qT3GaVvXqbcdawJUmU'
