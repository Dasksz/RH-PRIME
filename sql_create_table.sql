-- Create the main table for tracking EPI and Fardamento
create table if not exists public.funcionarios_epi (
  id uuid default gen_random_uuid() primary key,
  nome text not null,
  funcao text,
  unidade text default 'Padrão',
  admissao text,
  epi_data text,
  epi_link text,
  fardamento_data text,
  fardamento_link text,
  validacao text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable RLS
alter table public.funcionarios_epi enable row level security;

-- Create policies (Assuming authenticated users can read/write for now, based on previous auth setup)
create policy "Authenticated users can view data" on public.funcionarios_epi
  for select using (auth.role() = 'authenticated');

create policy "Authenticated users can update data" on public.funcionarios_epi
  for update using (auth.role() = 'authenticated');

create policy "Authenticated users can insert data" on public.funcionarios_epi
  for insert with check (auth.role() = 'authenticated');

create policy "Authenticated users can delete data" on public.funcionarios_epi
  for delete using (auth.role() = 'authenticated');

-- Enable Realtime
alter publication supabase_realtime add table public.funcionarios_epi;

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
