insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'photo-to-video-inputs',
  'photo-to-video-inputs',
  false,
  10485760,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = 10485760,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

do $$
begin
  if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='Users upload own photo-to-video inputs') then
    create policy "Users upload own photo-to-video inputs"
    on storage.objects for insert to authenticated
    with check (
      bucket_id = 'photo-to-video-inputs'
      and (storage.foldername(name))[1] = (select auth.uid())::text
    );
  end if;
  if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='Users read own photo-to-video inputs') then
    create policy "Users read own photo-to-video inputs"
    on storage.objects for select to authenticated
    using (
      bucket_id = 'photo-to-video-inputs'
      and (storage.foldername(name))[1] = (select auth.uid())::text
    );
  end if;
  if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='Users delete own photo-to-video inputs') then
    create policy "Users delete own photo-to-video inputs"
    on storage.objects for delete to authenticated
    using (
      bucket_id = 'photo-to-video-inputs'
      and (storage.foldername(name))[1] = (select auth.uid())::text
    );
  end if;
end $$;
