import json
import threading
import time
import requests
from .config import PUBLIC_KEY, get_secret, set_secret

class Database:
    def __init__(self, config):
        self.url = config['supabase_url'].rstrip('/')
        self.lock = threading.RLock()
        self.session = None

    def login(self, email, password):
        response = requests.post(self.url + '/auth/v1/token?grant_type=password',
            headers={'apikey': PUBLIC_KEY}, json={'email': email, 'password': password}, timeout=30)
        if not response.ok:
            raise ValueError('Login RH PRIME recusado. Confira e-mail e senha.')
        self._store(response.json())
        profile = self.rows('profiles', {'id': 'eq.' + self.session['user']['id']})
        if not profile or profile[0]['status'] != 'admin':
            self.logout()
            raise ValueError('O processador exige uma conta administradora aprovada.')

    def _store(self, session):
        self.session = session
        self.expires = time.time() + session.get('expires_in', 3600) - 90
        set_secret('supabase_refresh', session['refresh_token'])

    def token(self):
        with self.lock:
            if not self.session or time.time() >= self.expires:
                refresh = get_secret('supabase_refresh')
                if not refresh:
                    raise ValueError('Faça login no RH PRIME no aplicativo.')
                response = requests.post(self.url + '/auth/v1/token?grant_type=refresh_token',
                    headers={'apikey': PUBLIC_KEY}, json={'refresh_token': refresh}, timeout=30)
                if not response.ok:
                    raise ValueError('Sessão expirada. Faça login novamente.')
                self._store(response.json())
            return self.session['access_token']

    def logout(self):
        try:
            if self.session:
                requests.post(self.url + '/auth/v1/logout', headers={'apikey':PUBLIC_KEY,
                    'Authorization':'Bearer '+self.session['access_token']}, timeout=20)
        finally:
            self.session = None
            set_secret('supabase_refresh', '')

    def request(self, method, resource, body=None, params=None, prefer='return=representation'):
        response = requests.request(method, self.url + '/rest/v1/' + resource,
            headers={'apikey': PUBLIC_KEY, 'Authorization': 'Bearer ' + self.token(), 'Prefer': prefer},
            json=body, params=params, timeout=45)
        if not response.ok:
            # Do not include remote body, credentials, URLs with tokens, or sensitive payloads in logs.
            raise RuntimeError(f'Banco recusou operação ({response.status_code}) em {resource.split("?")[0]}.')
        return response.json() if response.content else None

    def rows(self, table, params=None):
        rows = []
        for offset in range(0, 1000000, 1000):
            page = self.request('GET', table, params={**(params or {}), 'limit':1000, 'offset':offset, 'order':'id'})
            rows.extend(page)
            if len(page) < 1000:
                return rows
        raise RuntimeError('Limite de paginação excedido.')

    def settings(self):
        rows = self.rows('rh_automation_settings')
        if not rows:
            raise ValueError('Configurações indisponíveis. Confira migração e permissão administrativa.')
        return rows[0]

    def employee(self, employee_id):
        rows = self.rows('funcionarios_epi', {'id':'eq.'+employee_id})
        if len(rows) != 1:
            raise ValueError('Cadastro do colaborador indisponível.')
        return rows[0]

    def patch(self, table, row_id, changes, **filters):
        return self.request('PATCH', table, changes, {'id':'eq.'+row_id, **filters})

    def rpc(self, name, data):
        return self.request('POST', 'rpc/'+name, data)
