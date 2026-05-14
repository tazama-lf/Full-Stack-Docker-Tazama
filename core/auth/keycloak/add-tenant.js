#!/usr/bin/env node
// add-tenant.js - Add a new tenant to a live Keycloak instance via Admin REST API.
//
// Usage:
//   node add-tenant.js --domain <domain> --tenant-id <TENANT_ID> --password <password>
//                      [--keycloak-url <url>] [--admin-user <user>] [--admin-password <pw>]
//                      [--realm <realm>] [--dry-run]
//
// Admin password defaults to KC_ADMIN_PW env var.

import https from 'node:https';
import { URLSearchParams } from 'node:url';

// ---------------------------------------------------------------------------
// User templates
// ---------------------------------------------------------------------------
const USER_TEMPLATES = [
  { prefix: 'cms-administrator',      first: 'CMS',    last: 'Administrator',    groups: ['/tazama-cms/CMS_ADMIN/{gd}'] },
  { prefix: 'cms-compliance-officer', first: 'CMS',    last: 'Compliance Officer', groups: ['/tazama-cms/CMS_COMPLIANCE_OFFICER/{gd}'] },
  { prefix: 'cms-investigator',       first: 'CMS',    last: 'Investigator',      groups: ['/tazama-cms/CMS_INVESTIGATOR/{gd}'] },
  { prefix: 'cms-supervisor',         first: 'CMS',    last: 'Supervisor',        groups: ['/tazama-cms/CMS_SUPERVISOR/{gd}'] },
  { prefix: 'tcs-approver',           first: 'TCS',    last: 'Approver',          groups: ['/tazama-tcs/approver/{gd}'] },
  { prefix: 'tcs-editor',             first: 'TCS',    last: 'Editor',            groups: ['/tazama-tcs/editor/{gd}'] },
  { prefix: 'tcs-exporter',           first: 'TCS',    last: 'Exporter',          groups: ['/tazama-tcs/exporter/{gd}'] },
  { prefix: 'tcs-publisher',          first: 'TCS',    last: 'Publisher',         groups: ['/tazama-tcs/publisher/{gd}'] },
  { prefix: 'trs-approver',           first: 'TRS',    last: 'Approver',          groups: ['/tazama-trs/approver/{gd}'] },
  { prefix: 'trs-editor',             first: 'TRS',    last: 'Editor',            groups: ['/tazama-trs/editor/{gd}'] },
  { prefix: 'trs-publisher',          first: 'TRS',    last: 'Publisher',         groups: ['/tazama-trs/publisher/{gd}'] },
  { prefix: 'tazama-api-client',      first: 'Tazama', last: 'API Client',        groups: ['/tazama-conditions/{gd}', '/tazama-config/{gd}', '/tazama-reports/{gd}', '/tazama-tms/{gd}'] },
];

// ---------------------------------------------------------------------------
// HTTP helper (stdlib only)
// ---------------------------------------------------------------------------
function request(method, url, { token, body, contentType = 'application/json' } = {}) {
  return new Promise((resolve, reject) => {
    const encoded = body
      ? (contentType === 'application/x-www-form-urlencoded'
          ? new URLSearchParams(body).toString()
          : JSON.stringify(body))
      : undefined;

    const parsed = new URL(url);
    const options = {
      hostname: parsed.hostname,
      port: parsed.port || 443,
      path: parsed.pathname + parsed.search,
      method,
      headers: {
        'Content-Type': contentType,
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(encoded ? { 'Content-Length': Buffer.byteLength(encoded) } : {}),
      },
    };

    const req = https.request(options, (res) => {
      let raw = '';
      res.on('data', (chunk) => (raw += chunk));
      res.on('end', () => {
        let data;
        try { data = raw ? JSON.parse(raw) : {}; } catch { data = raw; }
        resolve({ status: res.statusCode, data });
      });
    });
    req.on('error', reject);
    if (encoded) req.write(encoded);
    req.end();
  });
}

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------
async function getToken(baseUrl, adminUser, adminPassword) {
  const { status, data } = await request('POST',
    `${baseUrl}/realms/master/protocol/openid-connect/token`,
    { body: { grant_type: 'password', client_id: 'admin-cli', username: adminUser, password: adminPassword },
      contentType: 'application/x-www-form-urlencoded' });
  if (status !== 200) {
    console.error(`ERROR: Could not obtain admin token (HTTP ${status}):`, data);
    process.exit(1);
  }
  return data.access_token;
}

// ---------------------------------------------------------------------------
// Group helpers
// ---------------------------------------------------------------------------
async function findServiceGroup(baseUrl, realm, token, servicePathPrefix) {
  const name = servicePathPrefix.replace(/^\//, '');
  const { data } = await request('GET', `${baseUrl}/admin/realms/${realm}/groups`, { token });
  return Array.isArray(data) ? (data.find((g) => g.name === name)?.id ?? null) : null;
}

async function findChildGroup(baseUrl, realm, token, parentId, name) {
  // subGroups is always empty in Keycloak 23 - must use /children endpoint
  const { data } = await request('GET', `${baseUrl}/admin/realms/${realm}/groups/${parentId}/children`, { token });
  return Array.isArray(data) ? (data.find((g) => g.name === name)?.id ?? null) : null;
}

async function ensureSubgroup(baseUrl, realm, token, parentId, name, dryRun) {
  const existing = await findChildGroup(baseUrl, realm, token, parentId, name);
  if (existing) return existing;

  console.log(`  Create group '${name}' under parent ${parentId}`);
  if (dryRun) return `dry-run-group-${name}`;

  const { status, data } = await request('POST',
    `${baseUrl}/admin/realms/${realm}/groups/${parentId}/children`,
    { token, body: { name } });
  if (status === 201 || status === 409) {
    return await findChildGroup(baseUrl, realm, token, parentId, name);
  }
  console.error(`  ERROR creating group '${name}': HTTP ${status}`, data);
  process.exit(1);
}

// ---------------------------------------------------------------------------
// User helpers
// ---------------------------------------------------------------------------
async function findUser(baseUrl, realm, token, username) {
  const { data } = await request('GET',
    `${baseUrl}/admin/realms/${realm}/users?username=${encodeURIComponent(username)}&exact=true`,
    { token });
  return Array.isArray(data) && data.length ? data[0] : null;
}

async function createUser(baseUrl, realm, token, username, firstName, lastName, password, dryRun) {
  console.log(`  ${dryRun ? '[DRY-RUN] ' : ''}Create user ${username}`);
  if (dryRun) return `dry-run-user-${username}`;

  const domain = username.includes('@') ? username.split('@')[1] : '';
  const tenantId = domain.split('.')[0].toUpperCase();

  const { status, data } = await request('POST', `${baseUrl}/admin/realms/${realm}/users`, {
    token,
    body: {
      username, email: username, firstName, lastName,
      enabled: true, emailVerified: true,
      credentials: [{ type: 'password', value: password, temporary: false }],
      attributes: { TENANT_ID: [tenantId] },
    },
  });

  if (status === 201) {
    return (await findUser(baseUrl, realm, token, username))?.id ?? null;
  } else if (status === 409) {
    console.log(`    (user '${username}' already exists - updating password)`);
    const user = await findUser(baseUrl, realm, token, username);
    if (user) {
      await request('PUT', `${baseUrl}/admin/realms/${realm}/users/${user.id}/reset-password`, {
        token, body: { type: 'password', value: password, temporary: false },
      });
      return user.id;
    }
  } else {
    console.error(`  ERROR creating user '${username}': HTTP ${status}`, data);
  }
  return null;
}

async function assignUserToGroup(baseUrl, realm, token, userId, groupId, dryRun) {
  console.log(`    ${dryRun ? '[DRY-RUN] ' : ''}Assign user to group ${groupId}`);
  if (dryRun) return;
  const { status } = await request('PUT',
    `${baseUrl}/admin/realms/${realm}/users/${userId}/groups/${groupId}`, { token });
  if (![200, 204].includes(status)) {
    console.warn(`    WARNING: Could not assign group ${groupId} (HTTP ${status})`);
  }
}

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------
async function printTenantReport(baseUrl, realm, adminUser, adminPassword, tenantId, domain, password) {
  const token = await getToken(baseUrl, adminUser, adminPassword);
  const divider = '='.repeat(50);

  console.log(divider);
  console.log('TENANT ONBOARDING REPORT');
  console.log(divider);
  console.log(`TenantId: ${tenantId}`);
  console.log();
  console.log('https://cms.beta.tazama.org');
  for (const p of ['cms-administrator', 'cms-compliance-officer', 'cms-investigator', 'cms-supervisor'])
    console.log(`  ${p}@${domain}`);
  console.log();
  console.log('https://tcs.beta.tazama.org');
  for (const p of ['tcs-approver', 'tcs-editor', 'tcs-exporter', 'tcs-publisher'])
    console.log(`  ${p}@${domain}`);
  console.log();
  console.log('https://trs.beta.tazama.org');
  for (const p of ['trs-approver', 'trs-editor', 'trs-publisher'])
    console.log(`  ${p}@${domain}`);
  console.log();
  console.log('https://tms.beta.tazama.org');
  console.log('https://admin.beta.tazama.org');
  console.log();
  console.log(`  tazama-api-client@${domain}`);
  console.log();
  console.log(`password: ${password}`);
  console.log();

  console.log(divider);
  console.log('KEYCLOAK GROUP ASSIGNMENTS');
  console.log(divider);

  for (const { prefix } of USER_TEMPLATES) {
    const username = `${prefix}@${domain}`;
    const user = await findUser(baseUrl, realm, token, username);
    if (!user) { console.log(`  ${username}: (not found)`); continue; }
    const { data: groups } = await request('GET',
      `${baseUrl}/admin/realms/${realm}/users/${user.id}/groups`, { token });
    console.log(`  ${username}`);
    if (Array.isArray(groups)) groups.forEach((g) => console.log(`    -> ${g.path}`));
  }

  console.log(divider);
}

// ---------------------------------------------------------------------------
// CLI arg parsing (stdlib - no commander dependency)
// ---------------------------------------------------------------------------
function parseArgs() {
  const args = process.argv.slice(2);
  const get = (flag, def) => {
    const i = args.indexOf(flag);
    return i !== -1 ? args[i + 1] : def;
  };
  return {
    domain:        get('--domain', null),
    tenantId:      get('--tenant-id', null),
    password:      get('--password', null),
    keycloakUrl:   get('--keycloak-url', 'https://keycloak.beta.tazama.org'),
    adminUser:     get('--admin-user', 'admin'),
    adminPassword: get('--admin-password', process.env.KC_ADMIN_PW ?? 'password'),
    realm:         get('--realm', 'tazama'),
    dryRun:        args.includes('--dry-run'),
  };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
  const opts = parseArgs();
  if (!opts.domain || !opts.tenantId || !opts.password) {
    console.error('Usage: node add-tenant.js --domain <domain> --tenant-id <TENANT_ID> --password <password>');
    process.exit(1);
  }

  const domain      = opts.domain.toLowerCase();
  const groupDomain = domain.toUpperCase();
  const { realm, keycloakUrl: baseUrl, dryRun } = opts;

  console.log(`\n=== Add tenant: ${opts.tenantId} | domain: ${domain} | realm: ${realm} ===`);
  if (dryRun) console.log('*** DRY-RUN MODE - no changes will be made ***');

  // 1. Authenticate
  console.log('\n[1/4] Authenticating as admin...');
  let token = dryRun ? 'dry-run-token' : await getToken(baseUrl, opts.adminUser, opts.adminPassword);
  console.log('      OK');

  // 2. Ensure group structure
  console.log(`\n[2/4] Ensuring group subgroups for ${groupDomain}...`);
  const neededPaths = [...new Set(USER_TEMPLATES.flatMap((t) => t.groups.map((g) => g.replace('{gd}', groupDomain))))];
  const groupIdCache = {};

  for (const path of neededPaths.sort()) {
    const parts = path.replace(/^\//, '').split('/');
    let currentPath = '';
    let parentId = null;
    for (let i = 0; i < parts.length; i++) {
      currentPath += '/' + parts[i];
      if (groupIdCache[currentPath]) { parentId = groupIdCache[currentPath]; continue; }
      if (i === 0) {
        const gid = dryRun ? `dry-svc-${parts[i]}` : await findServiceGroup(baseUrl, realm, token, currentPath);
        if (!gid) { console.error(`  ERROR: Service group '${currentPath}' not found.`); process.exit(1); }
        groupIdCache[currentPath] = gid;
        parentId = gid;
      } else {
        const gid = await ensureSubgroup(baseUrl, realm, token, parentId, parts[i], dryRun);
        groupIdCache[currentPath] = gid;
        parentId = gid;
      }
    }
  }
  console.log('      Done.');

  // 3. Create users (refresh token per user)
  console.log(`\n[3/4] Creating ${USER_TEMPLATES.length} users...`);
  for (const { prefix, first, last, groups } of USER_TEMPLATES) {
    if (!dryRun) token = await getToken(baseUrl, opts.adminUser, opts.adminPassword);
    const username = `${prefix}@${domain}`;
    const userId = await createUser(baseUrl, realm, token, username, first, last, opts.password, dryRun);

    for (const gp of groups) {
      const fullPath = gp.replace('{gd}', groupDomain);
      const groupId = groupIdCache[fullPath];
      if (groupId) await assignUserToGroup(baseUrl, realm, token, userId, groupId, dryRun);
      else console.warn(`    WARNING: Group path '${fullPath}' not in cache, skipping`);
    }
  }

  console.log(`\n[4/4] Done. Tenant ${opts.tenantId} (${domain}) provisioned with ${USER_TEMPLATES.length} users.`);
  console.log(`      Users can log in at https://cms.beta.tazama.org etc. with their @${domain} email addresses.\n`);

  if (!dryRun) {
    await printTenantReport(baseUrl, realm, opts.adminUser, opts.adminPassword, opts.tenantId, domain, opts.password);
  }
}

main().catch((err) => { console.error(err); process.exit(1); });
