create table tenant (
  id uuid primary key default gen_random_uuid(),
  name text unique not null
);

alter table tenant enable row level security;

insert into tenant (id, name) values ('e4e4b158-1e8b-46ab-8f5d-dc510869d835', 'DEFAULT');

create table user_tenant (
  roleName text primary key,
  tenantId uuid not null references tenant(id) on delete cascade
);

create or replace function set_tenant_id(t uuid)
returns void as $$
begin
    perform set_config('public.tenant_id', t::text, true);
end;
$$ language plpgsql;

create or replace function current_tenant_id()
returns uuid language sql
security definer
set search_path = public
stable as
$$
    select coalesce(
               nullif(current_setting('public.tenantId', true), '')::uuid, 
               (select id 
                from public.tenant
                where name = 'DEFAULT'
                limit 1),
               (select ut.tenantId
                from public.user_tenant ut
                where ut.roleName = current_user
                limit 1)
           );
$$;

create table support_tenant_access (
  roleName text not null,
  tenantId uuid not null references tenant(id) on delete cascade,
  primary key (roleName, tenantid)
);
create index on support_tenant_access (tenantId);

create or replace function has_tenant(p_tenant_id uuid, u text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    -- regular user mapping: 1 role → 1 tenant
    select 1 from user_tenant ut
     where ut.roleName = u
       and ut.tenantId = p_tenant_id
    union all
    -- support-user mapping: 1 role → many tenants
    select 1 from support_tenant_access s
     where s.roleName = u
       and s.tenantId = p_tenant_id
  );
$$;

create policy tenants_visibility on tenant
  for select
  to public
  using (public.has_tenant(id, current_user));
