-- Store the category selected when a president posts an announcement.
alter table public.announcements
  add column if not exists category text not null default 'General Announcement';

update public.announcements
set category = 'General Announcement'
where category is null;

alter table public.announcements
  alter column category set default 'General Announcement',
  alter column category set not null;

comment on column public.announcements.category is
  'Announcement category selected by the president when posting.';
