// Each request requires a short-lived, single-use event capability verified in Postgres.
import { createClient } from 'npm:@supabase/supabase-js@2.58.0';
const client = createClient(Deno.env.get('SUPABASE_URL')!, (JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS') || '{}')['default'] || Deno.env.get('SUPABASE_PUBLISHABLE_KEY') || 'sb_publishable_UrTJ8_SyM3n800C4LZQWpw_5Ah8Ko98'), {
  auth: { persistSession: false, autoRefreshToken: false }
});
Deno.serve(async (req: Request) => {
  const response = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
    status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }
  });
  if (req.method !== 'POST') return response({ error: 'Método inválido' }, 405);
  try {
    const text = await req.text();
    if (text.length > 2048) return response({ error: 'Pedido inválido' }, 400);
    const b = JSON.parse(text);
    if (!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(b.eventId || '') ||
        !/^[a-f0-9]{64}$/.test(b.eventToken || '') || !['claim', 'complete'].includes(b.action)) {
      return response({ error: 'Evento inválido' }, 403);
    }
    const args: Record<string, unknown> = { p_id: b.eventId, p_token: b.eventToken };
    if (b.action === 'complete') {
      if (typeof b.success !== 'boolean') return response({ error: 'Resultado inválido' }, 400);
      args.p_success = b.success;
    }
    const { data, error } = await client.rpc('rh_notification_' + b.action, args);
    if (error) return response({ error: 'Evento indisponível ou não autorizado' }, 403);
    return response(b.action === 'claim' ? data : { recorded: true });
  } catch (_) { return response({ error: 'Pedido inválido' }, 400); }
});
