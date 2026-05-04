
-- ==========================================
-- 1. CONFIGURAÇÃO DE AUTENTICAÇÃO E PERFIS
-- ==========================================
-- Create a table for public profiles
create table if not exists public.profiles (
  id uuid references auth.users on delete cascade not null primary key,
  name text not null,
  email text not null,
  status text not null default 'pendente',
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Set up Row Level Security (RLS)
alter table public.profiles enable row level security;

-- Policies
drop policy if exists "Public profiles are viewable by everyone." on public.profiles;
create policy "Public profiles are viewable by everyone." on public.profiles
  for select using (true);

drop policy if exists "Users can update own profile." on public.profiles;
create policy "Users can update own profile." on public.profiles
  for update using (auth.uid() = id);

drop policy if exists "Admins can update all profiles." on public.profiles;
create policy "Admins can update all profiles." on public.profiles
  for update using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and status = 'admin'
    )
  );

-- Function to handle new user signups
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, name, email, status)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', 'Usuário sem nome'),
    new.email,
    'pendente'
  );
  return new;
end;
$$ language plpgsql security definer;

-- Trigger for new user signup
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- ==========================================
-- 2. TABELA DE EPI E FARDAMENTOS E REALTIME
-- ==========================================
-- Create the main table for tracking EPI and Fardamento
create table if not exists public.funcionarios_epi (
  id uuid default gen_random_uuid() primary key,
  nome text not null,
  cpf text,
  funcao text,
  unidade text default 'Padrão',
  admissao text,
  epi_data text,
  epi_link text,
  fardamento_data text,
  fardamento_link text,
  epi_itens text,
  fardamento_itens text,
  validacao text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable RLS
alter table public.funcionarios_epi enable row level security;

-- Create policies (Assuming authenticated users can read/write for now, based on previous auth setup)
drop policy if exists "Authenticated users can view data" on public.funcionarios_epi;
create policy "Authenticated users can view data" on public.funcionarios_epi
  for select using (auth.role() = 'authenticated');

drop policy if exists "Authenticated users can update data" on public.funcionarios_epi;
create policy "Authenticated users can update data" on public.funcionarios_epi
  for update using (auth.role() = 'authenticated');

drop policy if exists "Authenticated users can insert data" on public.funcionarios_epi;
create policy "Authenticated users can insert data" on public.funcionarios_epi
  for insert with check (auth.role() = 'authenticated');

drop policy if exists "Authenticated users can delete data" on public.funcionarios_epi;
create policy "Authenticated users can delete data" on public.funcionarios_epi
  for delete using (auth.role() = 'authenticated');

-- Enable Realtime safely
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'funcionarios_epi'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.funcionarios_epi;
    END IF;
END
$$;

-- Trigger to update updated_at timestamp
create or replace function update_modified_column()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

drop trigger if exists update_funcionarios_epi_modtime on public.funcionarios_epi;
create trigger update_funcionarios_epi_modtime
    before update on public.funcionarios_epi
    for each row
    execute function update_modified_column();


-- ==========================================
-- 3. INSERÇÃO DOS DADOS INICIAIS DA PLANILHA
-- ==========================================
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('ADRIANO SANTOS DE ANDRADE', '', '20/03/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('AGNALDO AGUIAR DE OLIVEIRA', '', '01/05/2024', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('ALEILSON AMORIM SANTOS', '', '01/07/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('ALINE SANTOS SOARES', '', '02/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('ANTONIO CARLOS DE SANTANA NASCIMENTO', '', '22/07/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('ARIANA TEIXEIRA DOS SANTOS', '', '06/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('CIRO SILVA DA SILVA', '', '14/11/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('DANIEL DOS SANTOS CESAR', '', '06/02/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('DIEGO MACIEL DOS SANTOS', '', '16/12/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('EDINAELSON DOS SANTOS', '', '05/01/2026', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('EDINALDO PEREIRA LIMA', '', '06/10/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('ELENILTON DOS SANTOS SOARES', '', '01/12/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('EVANILDO DE JESUS OLIVEIRA JUNIOR', '', '17/12/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('EVITON DIAS GARCIA', '', '12/04/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('FABIANO SANTOS BARRETO', '', '24/02/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('FABRICIO SOUZA DE SA', '', '06/06/2024', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('FELIPE DE OLIVEIRA RAMOS', '', '15/12/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('FELIPE OLIVEIRA DA SILVA', '', '06/11/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('FELIPE OLIVEIRA DE JESUS', 'ASSISTENTE DE VENDAS', '20/04/2026', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('GEIR MOURA DA SILVA JUNIOR', '', '19/05/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('GEISA DA SILVA RODRIGUES', '', '02/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('GEOVANE OLIVEIRA CERQUEIRA DE CARVALHO', '', '02/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('GILBERTO AZEVEDO GOES', '', '02/04/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('GILMAR CAVALCANTE DE ARAUJO', '', '02/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('GILVAN BRITO BRUNO', '', '23/12/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('GIULIANO FERNANDES CESARINO', '', '05/05/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('GUSTAVO NEVES PEREIRA DA SILVA', '', '02/09/2024', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('HANIEL OLIVEIRA DE JESUS DE LIMA', '', '22/04/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('HELIO CARLOS SILVA OLIVEIRA', '', '11/03/2026', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('ILMARA BARROS SAMPAIO', '', '02/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('IRINEU OLIVEIRA SANTOS', '', '28/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('JAILSON DOS SANTOS ALMEIDA', '', '02/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('JAIME QUEIROZ SANTANA', '', '02/03/2026', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('JOSE CARLOS VIEIRA', '', '02/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('JOSE RAIMUNDO FERREIRA DA SILVA', '', '02/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('JOSE SANTOS CESARIO SILVA', '', '22/12/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('JOSUE ALMEIDA BARRETO NETO', '', '02/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('JUALAS FIDELIS DOS SANTOS', '', '05/05/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('JUARES DOS SANTOS VIEIRA', '', '01/06/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('JUAREZ FONTES DE JESUS', '', '01/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('JULIO ESPIRITO SANTO NASCIMENTO NETO', '', '02/01/2024', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('KALINE PEREIRA BARBOSA', '', '11/03/2024', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('KARINA RIBEIRO MENDONÇA', '', '04/02/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('LAIANE SANTOS DOS REIS', '', '06/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('LAYSA SILVA BASTOS', '', '01/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('LEANDRO DE MATOS SANTOS', '', '06/01/2026', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('LENNON RAMOS LIMA', 'AUXILIAR ADMINISTRATIVO', '18/12/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('LEONARDO CRISTIANO DA SILVA MARTINS', '', '02/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('LEONIR SOUTO DOS SANTOS', '', '02/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('LOURIVALDO NERY DE SOUZA FILHO', '', '07/04/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('LUCAS SENA TELLES DOS SANTOS', '', '19/03/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('LUCIANO DE LIMA CAMPOS', '', '10/03/2026', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('LUIS GUSTAVO JESUS SANTANA', '', '02/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('LUIZ CARLOS TELES SILVA', '', '02/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('MARCEL BURAK MENDES PIRES', '', '13/05/2024', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('MARCELO DOS SANTOS', '', '23/02/2026', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('MARCONE DE JESUS SANTOS', '', '28/03/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('MARCOS ALVES DE HUNGRIA', '', '11/03/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('MARCOS WILKER COSTA DE ARAUJO', '', '05/01/2026', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('MARIA LILIAN SANTOS DE SANTANA', '', '08/04/2024', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('MATHEUS SOUZA MORAES DOS SANTOS', '', '02/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('MAURICIO NUNES OLIVEIRA', '', '01/08/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('MAX DE ARAUJO SANTOS', '', '11/04/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('PEDRO THIAGO ROCHA DA SILVA', '', '01/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('PETTERSON DE JESUS BISPO DOS SANTOS', '', '15/12/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('RANIERE NEVES MELO', '', '02/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('REINALDO SILVA NASCIMENTO', '', '26/12/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('ROMULO AMADO DA SILVA', '', '15/09/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('SARA PEREIRA PEIXOTO', '', '06/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('THAIS SANTOS SILVA', '', '08/04/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('THIAGO DOS SANTOS RAMOS', '', '09/03/2026', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('THIAGO JOSE DE SOUZA GOMES', '', '19/11/2024', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('TIAGO DA PAIXÃO DOS SANTOS', '', '02/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('UALISON NASCIMENTO DA SILVA', '', '08/05/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('UBIRATAN DE ANDRADE SILVA', '', '13/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('UBIRATAN SILVA DE SOUZA', '', '02/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('VALNEI NOVAIS DE CARVALHO', '', '02/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('VANESSIA SANTOS BATISTA', '', '02/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('VICTOR OLIVEIRA CARDEAL', '', '22/04/2026', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('WADSON ARAUJO DA SILVA', '', '02/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('WANDER RIBEIRO DOS SANTOS', '', '06/01/2025', '', '', '', '', '');
INSERT INTO public.funcionarios_epi (nome, funcao, admissao, epi_data, epi_link, fardamento_data, fardamento_link, validacao) VALUES ('WILDO DIAS GOMES', '', '06/01/2025', '', '', '', '', '');
