create table tenant (
  id text primary key default gen_random_uuid()::text,
  name text unique not null
);

alter table tenant enable row level security;

insert into tenant (id, name) values ('DEFAULT', 'DEFAULT');

create table user_tenant (
  roleName text primary key,
  tenantId text not null references tenant(id) on delete cascade
);

create or replace function set_tenant_id(t text)
returns void as $$
begin
    perform set_config('public.tenant_id', t, true);
end;
$$ language plpgsql;

create or replace function current_tenant_id()
returns text language sql
security definer
set search_path = public
stable as
$$
    select coalesce(
               nullif(current_setting('public.tenantId', true), '')::text, 
               (select id 
                from public.tenant
                where id = 'DEFAULT'
                limit 1),
               (select ut.tenantId
                from public.user_tenant ut
                where ut.roleName = current_user
                limit 1)
           );
$$;

create table support_tenant_access (
  roleName text not null,
  tenantId text not null references tenant(id) on delete cascade,
  primary key (roleName, tenantid)
);
create index on support_tenant_access (tenantId);

create or replace function has_tenant(p_tenant_id text, u text)
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
