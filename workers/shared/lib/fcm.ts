type ServiceAccountInfo = {
  client_email: string;
  private_key: string;
  project_id?: string;
};

export type LoadedServiceAccount = {
  clientEmail: string;
  privateKeyPem: string;
  projectId: string;
};

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const OAUTH_TOKEN_URL = 'https://oauth2.googleapis.com/token';

function isTruthy(value: string | undefined): boolean {
  if (!value) return false;
  return ['1', 'true', 'yes', 'y', 'on'].includes(value.trim().toLowerCase());
}

function decodeBase64ToString(input: string): string {
  const text = input.trim();
  if (typeof atob !== 'function') {
    throw new Error('Base64 decode is not available in this runtime');
  }
  return atob(text);
}

function base64UrlEncodeBytes(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  const b64 = btoa(binary);
  return b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const normalized = pem.replace(/\\n/g, '\n').trim();
  const body = normalized
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '');

  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

async function importRsaPrivateKey(pkcs8: ArrayBuffer): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    'pkcs8',
    pkcs8,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign'],
  );
}

async function signJwtRs256(privateKey: CryptoKey, payload: Record<string, unknown>): Promise<string> {
  const encoder = new TextEncoder();
  const header = { alg: 'RS256', typ: 'JWT' };

  const headerPart = base64UrlEncodeBytes(encoder.encode(JSON.stringify(header)));
  const payloadPart = base64UrlEncodeBytes(encoder.encode(JSON.stringify(payload)));
  const signingInput = `${headerPart}.${payloadPart}`;

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    encoder.encode(signingInput),
  );
  const signaturePart = base64UrlEncodeBytes(new Uint8Array(signature));
  return `${signingInput}.${signaturePart}`;
}

export function loadServiceAccountFromEnv(rawEnvValue: string, explicitProjectId?: string): LoadedServiceAccount {
  const raw = rawEnvValue.trim();
  const jsonText = raw.startsWith('{') ? raw : decodeBase64ToString(raw);

  let info: ServiceAccountInfo;
  try {
    info = JSON.parse(jsonText) as ServiceAccountInfo;
  } catch {
    throw new Error('Failed to parse FCM service account JSON');
  }

  const clientEmail = (info.client_email || '').trim();
  const privateKeyPem = (info.private_key || '').trim();
  const projectId = (explicitProjectId || info.project_id || '').trim();

  if (!clientEmail) throw new Error('Service account missing client_email');
  if (!privateKeyPem) throw new Error('Service account missing private_key');
  if (!projectId) throw new Error('Service account missing project_id (or set FCM_PROJECT_ID)');

  return { clientEmail, privateKeyPem, projectId };
}

export async function getFcmAccessToken(serviceAccount: LoadedServiceAccount): Promise<string> {
  const iat = Math.floor(Date.now() / 1000);
  const exp = iat + 3600;

  const pkcs8 = pemToPkcs8(serviceAccount.privateKeyPem);
  const key = await importRsaPrivateKey(pkcs8);

  const jwt = await signJwtRs256(key, {
    iss: serviceAccount.clientEmail,
    scope: FCM_SCOPE,
    aud: OAUTH_TOKEN_URL,
    iat,
    exp,
  });

  const form = new URLSearchParams();
  form.set('grant_type', 'urn:ietf:params:oauth:grant-type:jwt-bearer');
  form.set('assertion', jwt);

  const response = await fetch(OAUTH_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form.toString(),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Google OAuth token error ${response.status}: ${text}`);
  }

  const data = await response.json() as { access_token?: string };
  const token = (data.access_token || '').trim();
  if (!token) throw new Error('Google OAuth token response missing access_token');
  return token;
}

export async function sendPushV1(params: {
  accessToken: string;
  projectId: string;
  deviceToken: string;
  title: string;
  body: string;
  data: Record<string, string>;
  dryRun?: boolean;
}): Promise<void> {
  if (params.dryRun) {
    console.log('DRY RUN: would send to', params.deviceToken, params.data);
    return;
  }

  const url = `https://fcm.googleapis.com/v1/projects/${params.projectId}/messages:send`;
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${params.accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      message: {
        token: params.deviceToken,
        notification: { title: params.title, body: params.body },
        data: params.data,
      },
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`FCM error ${response.status}: ${text}`);
  }
}

export function shouldDryRun(envValue: string | undefined): boolean {
  return isTruthy(envValue);
}
