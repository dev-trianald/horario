alter table public.tasks
    add column if not exists completed boolean not null default false;