create table public.tasks (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    day text not null,
    subject text not null,
    message text not null check (char_length(trim(message)) > 0),
    color text not null,
    week_start date not null default date_trunc('week', current_date)::date,
    is_exam boolean not null default false,
    completed boolean not null default false,
    created_at timestamptz not null default now()
);

create index tasks_user_created_at_idx on public.tasks (user_id, created_at desc);

alter table public.tasks enable row level security;

grant select, insert, update, delete on public.tasks to authenticated;

create policy "Users can read their own tasks"
    on public.tasks for select to authenticated
    using ((select auth.uid()) = user_id);

create policy "Users can create their own tasks"
    on public.tasks for insert to authenticated
    with check ((select auth.uid()) = user_id);

create policy "Users can update their own tasks"
    on public.tasks for update to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

create policy "Users can delete their own tasks"
    on public.tasks for delete to authenticated
    using ((select auth.uid()) = user_id);

create table public.reminders (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    subject text not null,
    message text not null check (char_length(trim(message)) > 0),
    completed boolean not null default false,
    created_at timestamptz not null default now()
);

create index reminders_user_created_at_idx on public.reminders (user_id, created_at desc);

alter table public.reminders enable row level security;

grant select, insert, update, delete on public.reminders to authenticated;

create policy "Users can read their own reminders"
    on public.reminders for select to authenticated
    using ((select auth.uid()) = user_id);

create policy "Users can create their own reminders"
    on public.reminders for insert to authenticated
    with check ((select auth.uid()) = user_id);

create policy "Users can update their own reminders"
    on public.reminders for update to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

create policy "Users can delete their own reminders"
    on public.reminders for delete to authenticated
    using ((select auth.uid()) = user_id);