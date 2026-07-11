-- =====================================================================
-- إعداد قاعدة بيانات منصة تسجيل دورة P3O® Foundation — TRACKFORD
-- شغّل هذا الملف كاملًا في Supabase → SQL Editor (آمن لإعادة التشغيل)
-- =====================================================================

-- 1) جدول المسجلين -----------------------------------------------------
create table if not exists public.registrations (
  id uuid primary key default gen_random_uuid(),
  reg_seq bigint generated always as identity,
  full_name text not null,
  email text not null,
  phone text not null,
  country text not null,
  city text not null,
  organization text not null,
  job_title text not null,
  source text not null,
  created_at timestamptz not null default now()
);

-- قيود فريدة لمنع التكرار (تُضاف فقط إن لم تكن موجودة)
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'registrations_email_key') then
    alter table public.registrations add constraint registrations_email_key unique (email);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'registrations_phone_key') then
    alter table public.registrations add constraint registrations_phone_key unique (phone);
  end if;
end $$;

-- 2) الحماية على مستوى الصفوف (RLS) ------------------------------------
alter table public.registrations enable row level security;

-- السماح للزائر بالإدخال فقط (احتياطي — التسجيل الأساسي يتم عبر الدالة أدناه)
drop policy if exists "Allow public insert" on public.registrations;
create policy "Allow public insert"
on public.registrations
for insert
to anon
with check (true);

-- السماح للإدارة (المسجلة دخولها عبر Supabase Auth) بقراءة البيانات فقط
drop policy if exists "Allow authenticated select" on public.registrations;
create policy "Allow authenticated select"
on public.registrations
for select
to authenticated
using (true);

-- 3) دالة التسجيل الآمنة (الإصلاح الأساسي) ------------------------------
-- تُدخل التسجيل وتعيد رقم التسلسل (reg_seq) دون الحاجة لصلاحية SELECT للزائر.
-- هذا يحل مشكلة فشل التسجيل السابقة الناتجة عن insert().select() مع RLS.
create or replace function public.register_trainee(
  p_full_name text,
  p_email text,
  p_phone text,
  p_country text,
  p_city text,
  p_organization text,
  p_job_title text,
  p_source text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seq bigint;
begin
  -- تحقق أساسي من المدخلات
  if coalesce(trim(p_full_name), '') = '' or
     coalesce(trim(p_email), '') = '' or
     coalesce(trim(p_phone), '') = '' then
    raise exception 'بيانات ناقصة' using errcode = '22023';
  end if;

  insert into public.registrations
    (full_name, email, phone, country, city, organization, job_title, source)
  values
    (trim(p_full_name),
     lower(trim(p_email)),
     trim(p_phone),
     trim(p_country),
     trim(p_city),
     trim(p_organization),
     trim(p_job_title),
     trim(p_source))
  returning reg_seq into v_seq;

  return v_seq;
end;
$$;

grant execute on function public.register_trainee(text, text, text, text, text, text, text, text)
  to anon, authenticated;

-- 4) دالة عدّاد المسجلين (لعداد المقاعد المتبقية) ------------------------
create or replace function public.get_registration_count()
returns integer
language sql
security definer
set search_path = public
as $$
  select count(*)::integer from public.registrations;
$$;

grant execute on function public.get_registration_count() to anon, authenticated;

-- =====================================================================
-- انتهى — لا تنسَ إنشاء حساب الإدارة من Authentication → Users
-- (Add user → Create new user مع تفعيل Auto Confirm User)
-- =====================================================================
