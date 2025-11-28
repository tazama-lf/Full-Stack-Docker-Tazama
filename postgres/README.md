# About Multi-Tenant Row-Level Security

## Features

- **Tenant isolation**  
  Regular tenant users can only see data that belongs to their own tenant.

- **Support / admin visibility**  
  Special “support” roles can be granted access to **one or more tenants**.

The pattern allows for flexibility - you can add business tables, as long as they have a `tenant_id` and use the provided RLS helpers.

---

## High-Level Design

### 1. Schema and Core Tables

All objects live in the `public` schema.

Tenants are registered in the `tenant` table:

- **Tenants** - `tenant` table tracks all tenants registered in the system

* **User → Tenant mapping** - tracks all the postgres roles for the tenants

* **Support user → Tenant mapping** - maps a **support role** to **one or many tenants**.

All business tables must include a `tenant_id` column referencing `public.tenant(id)`.

---

### 2. Tenant Resolution

The design uses a **GUC (custom setting)** as well as some helper functions to figure out which tenant to use:

Lookup order:

1. **Explicit GUC**: value set via `public.set_tenant_id(...)`
2. **DEFAULT tenant**: row where `name = 'DEFAULT'`
3. **User mapping**: `public.user_tenant` row for `current_user`

## Typical Workflow

### 1. Insert data as DEFAULT tenant

As `postgres`:

```sql
INSERT INTO public.pacs008 (document) VALUES ('{}');
```

* `tenant_id` will be set to the `DEFAULT` tenant (assuming configured as such).

Check visibility:

```sql
SET ROLE foo_rw;
SELECT * FROM public.pacs008;  -- no rows

SET ROLE bar_rw;
SELECT * FROM public.pacs008;  -- no rows

RESET ROLE;                 -- back to postgres
SELECT * FROM public.pacs008;  -- sees row(s)
```

## Quick Recipes

### Create a new tenant

```sql
CREATE ROLE new_tenant LOGIN PASSWORD 'secret';

INSERT INTO public.tenant (name) VALUES ('New Tenant');

INSERT INTO public.user_tenant(roleName, tenantId)
VALUES (
  'new_tenant',
  (SELECT id FROM public.tenant WHERE name = 'New Tenant')
);

GRANT USAGE ON SCHEMA public TO new_tenant;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pacs008 TO new_tenant;
```

### Create a new support user

```sql
CREATE ROLE new_support LOGIN PASSWORD '12345';

GRANT USAGE ON SCHEMA public TO new_support;
GRANT SELECT ON public.pacs008 TO new_support;
GRANT SELECT ON public.tenant TO new_support;

INSERT INTO public.support_tenant_access(roleName, tenantId)
VALUES (
  'new_support',
  (SELECT id FROM public.tenant WHERE name = 'Tenant Name')
);
```

---

## Important Notes

* The `'DEFAULT'` tenant name is **reserved** for fallback cases.
* RLS is enforced for all non-superusers; you don’t need to add `WHERE tenant_id = ...` clauses in application queries.
* Applications should:

  * Set a connection role (`SET ROLE ...`), and
  * Optionally call `public.set_tenant_id(...)` at the start of a transaction if they need explicit tenant scoping.
