alter table public.tasks
    add column if not exists week_start date;

update public.tasks
set week_start = date_trunc('week', created_at)::date
where week_start is null;

alter table public.tasks
    alter column week_start set default date_trunc('week', current_date)::date,
    alter column week_start set not null;

alter table public.tasks
    add column if not exists is_exam boolean not null default false;