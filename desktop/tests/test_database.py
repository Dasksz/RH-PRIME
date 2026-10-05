import unittest
from unittest.mock import patch, Mock
from rhprime.database import Database

class SessionTests(unittest.TestCase):
    @patch('rhprime.database.set_secret')
    @patch('rhprime.database.requests.post')
    def test_logout_clears_local_token_even_offline(self, post, secret):
        db = Database({'supabase_url':'https://example.invalid'})
        db.session = {'access_token':'synthetic'}
        post.side_effect = ConnectionError('offline')
        with self.assertRaises(ConnectionError): db.logout()
        self.assertIsNone(db.session)
        secret.assert_called_once_with('supabase_refresh','')

    @patch('rhprime.database.set_secret')
    @patch('rhprime.database.get_secret', return_value='saved-refresh')
    @patch('rhprime.database.requests.post')
    def test_saved_session_refreshes_without_password(self, post, get, save):
        post.return_value = Mock(ok=True)
        post.return_value.json.return_value = {'access_token':'new-access','refresh_token':'new-refresh','expires_in':3600}
        db = Database({'supabase_url':'https://example.invalid'})
        self.assertEqual(db.token(),'new-access')
        self.assertEqual(db.token(),'new-access')
        self.assertEqual(post.call_count,1)
        self.assertEqual(post.call_args.kwargs['json'],{'refresh_token':'saved-refresh'})
        save.assert_called_once_with('supabase_refresh','new-refresh')

if __name__ == '__main__': unittest.main()
