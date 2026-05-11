type Env = {
  FIREBASE_PROJECT_ID: string;
  FIREBASE_CLIENT_EMAIL: string;
  FIREBASE_PRIVATE_KEY: string;
};

type FirebaseConfig = {
  projectId: string;
  clientEmail: string;
  privateKey: string;
};

type SosRequestBody = {
  userId?: unknown;
  familyUid?: unknown;
  userName?: unknown;
  lat?: unknown;
  lng?: unknown;
  batteryLevel?: unknown;
  currentTripId?: unknown;
};

type TestFcmRequestBody = {
  token?: unknown;
  title?: unknown;
  body?: unknown;
  userId?: unknown;
  lat?: unknown;
  lng?: unknown;
};

const firebaseMessagingScope =
  'https://www.googleapis.com/auth/firebase.messaging';
const firebaseMessagingAndDatastoreScope =
  'https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/datastore';
const googleOAuthTokenUrl = 'https://oauth2.googleapis.com/token';
const sosEmergencyChannelId = 'sos_emergency_channel';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: corsHeaders,
      });
    }

    const url = new URL(request.url);

    if (url.pathname === '/config-check') {
      return handleConfigCheck(request, env);
    }

    if (url.pathname === '/test-fcm') {
      return handleTestFcm(request, env);
    }

    if (url.pathname === '/send-sos') {
      return handleSendSos(request, env);
    }

    return jsonResponse(
      {
        success: false,
        message: 'Endpoint not found',
      },
      404,
    );
  },
};

function handleConfigCheck(request: Request, env: Env): Response {
  if (request.method !== 'GET') {
    return jsonResponse(
      {
        success: false,
        message: 'Method not allowed. Use GET /config-check',
      },
      405,
      {
        Allow: 'GET, OPTIONS',
      },
    );
  }

  const firebaseConfig = getFirebaseConfig(env);
  const projectIdConfigured = firebaseConfig.projectId.length > 0;
  const clientEmailConfigured = firebaseConfig.clientEmail.length > 0;
  const privateKeyConfigured = firebaseConfig.privateKey.length > 0;

  if (!projectIdConfigured || !clientEmailConfigured || !privateKeyConfigured) {
    return jsonResponse(
      {
        success: false,
        message: 'Firebase configuration is incomplete',
      },
      500,
    );
  }

  return jsonResponse({
    success: true,
    firebaseConfig: {
      projectIdConfigured,
      clientEmailConfigured,
      privateKeyConfigured,
    },
  });
}

async function handleSendSos(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return jsonResponse(
      {
        success: false,
        message: 'Method not allowed. Use POST /send-sos',
      },
      405,
      {
        Allow: 'POST, OPTIONS',
      },
    );
  }

  const body = await parseJsonBody<SosRequestBody>(request);
  if (!body.ok) {
    return jsonResponse(
      {
        success: false,
        message: 'Invalid JSON body',
      },
      400,
    );
  }

  const validationError = validateSosBody(body.value);
  if (validationError !== null) {
    return jsonResponse(
      {
        success: false,
        message: validationError,
      },
      400,
    );
  }

  try {
    const result = await sendSosNotification(env, body.value);

    if (result.tokenCount === 0) {
      return jsonResponse(
        {
          success: false,
          message: 'No FCM tokens found for this family user',
        },
        404,
      );
    }

    return jsonResponse({
      success: true,
      message: 'SOS notification sent',
      sentCount: result.sentCount,
      failedCount: result.failedCount,
    });
  } catch (error) {
    return jsonResponse(
      {
        success: false,
        message: 'Failed to send SOS notification',
        error: toPublicError(error),
      },
      500,
    );
  }
}

async function handleTestFcm(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return jsonResponse(
      {
        success: false,
        message: 'Method not allowed. Use POST /test-fcm',
      },
      405,
      {
        Allow: 'POST, OPTIONS',
      },
    );
  }

  const body = await parseJsonBody<TestFcmRequestBody>(request);
  if (!body.ok) {
    return jsonResponse(
      {
        success: false,
        message: 'Invalid JSON body',
      },
      400,
    );
  }

  if (isBlankString(body.value.token)) {
    return jsonResponse(
      {
        success: false,
        message: 'token is required',
      },
      400,
    );
  }

  try {
    const fcmResponse = await sendTestFcmMessage(env, body.value);

    return jsonResponse({
      success: true,
      message: 'FCM notification sent',
      fcmResponse,
    });
  } catch (error) {
    return jsonResponse(
      {
        success: false,
        message: 'Failed to send FCM notification',
        error: toPublicError(error),
      },
      500,
    );
  }
}

async function sendTestFcmMessage(
  env: Env,
  body: TestFcmRequestBody,
): Promise<unknown> {
  const firebaseConfig = getFirebaseConfig(env);
  if (
    firebaseConfig.projectId.length === 0 ||
    firebaseConfig.clientEmail.length === 0 ||
    firebaseConfig.privateKey.length === 0
  ) {
    throw new Error('Firebase configuration is incomplete');
  }

  const accessToken = await getAccessToken(env, firebaseMessagingScope);
  const url =
    `https://fcm.googleapis.com/v1/projects/` +
    `${encodeURIComponent(firebaseConfig.projectId)}/messages:send`;

  const title = getOptionalString(body.title) ?? '\u{1F6A8} SOS Darurat';
  const notificationBody =
    getOptionalString(body.body) ?? 'Pengguna membutuhkan bantuan segera';
  const userId = getOptionalString(body.userId) ?? '';
  const lat = optionalStringValue(body.lat);
  const lng = optionalStringValue(body.lng);

  const fcmResponse = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      message: {
        token: body.token,
        notification: {
          title,
          body: notificationBody,
        },
        data: {
          type: 'sos',
          userId,
          lat,
          lng,
        },
        android: {
          priority: 'HIGH',
          notification: {
            channel_id: sosEmergencyChannelId,
            sound: 'default',
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
        },
      },
    }),
  });

  const responseBody = await readJsonOrText(fcmResponse);
  if (!fcmResponse.ok) {
    throw new Error(JSON.stringify(responseBody));
  }

  return responseBody;
}

async function sendSosNotification(
  env: Env,
  data: SosRequestBody,
): Promise<{ tokenCount: number; sentCount: number; failedCount: number }> {
  const familyUid = getRequiredString(data.familyUid);
  const accessToken = await getAccessToken(
    env,
    firebaseMessagingAndDatastoreScope,
  );
  const tokens = await getFamilyFcmTokens(env, familyUid, accessToken);

  if (tokens.length === 0) {
    return {
      tokenCount: 0,
      sentCount: 0,
      failedCount: 0,
    };
  }

  let sentCount = 0;
  let failedCount = 0;

  await Promise.all(
    tokens.map(async (token) => {
      try {
        await sendFcmToToken(env, accessToken, token, createSosFcmPayload(data));
        sentCount += 1;
      } catch {
        failedCount += 1;
      }
    }),
  );

  return {
    tokenCount: tokens.length,
    sentCount,
    failedCount,
  };
}

async function getFamilyFcmTokens(
  env: Env,
  familyUid: string,
  accessToken?: string,
): Promise<string[]> {
  const firebaseConfig = getFirebaseConfig(env);
  assertFirebaseConfig(firebaseConfig);

  const token =
    accessToken ??
    (await getAccessToken(env, firebaseMessagingAndDatastoreScope));
  const url =
    `https://firestore.googleapis.com/v1/projects/` +
    `${encodeURIComponent(firebaseConfig.projectId)}` +
    `/databases/(default)/documents/users/` +
    `${encodeURIComponent(familyUid)}/fcmTokens`;

  const response = await fetch(url, {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${token}`,
    },
  });

  if (response.status === 404) {
    return [];
  }

  const body = await readJsonOrText(response);
  if (!response.ok) {
    throw new Error(JSON.stringify(body));
  }

  if (!isRecord(body) || !Array.isArray(body.documents)) {
    return [];
  }

  const tokens: string[] = [];
  for (const document of body.documents) {
    const fcmToken = readFirestoreStringField(document, 'token');
    if (fcmToken !== null) {
      tokens.push(fcmToken);
    }
  }

  return [...new Set(tokens)];
}

async function sendFcmToToken(
  env: Env,
  accessToken: string,
  token: string,
  payload: Record<string, unknown>,
): Promise<unknown> {
  const firebaseConfig = getFirebaseConfig(env);
  assertFirebaseConfig(firebaseConfig);

  const url =
    `https://fcm.googleapis.com/v1/projects/` +
    `${encodeURIComponent(firebaseConfig.projectId)}/messages:send`;

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      message: {
        token,
        ...payload,
      },
    }),
  });

  const body = await readJsonOrText(response);
  if (!response.ok) {
    throw new Error(JSON.stringify(body));
  }

  return body;
}

function createSosFcmPayload(data: SosRequestBody): Record<string, unknown> {
  const userId = getRequiredString(data.userId);
  const familyUid = getRequiredString(data.familyUid);
  const userName = getRequiredString(data.userName);

  return {
    notification: {
      title: '\u{1F6A8} SOS Darurat',
      body: `${userName} membutuhkan bantuan segera`,
    },
    data: {
      type: 'sos',
      userId,
      familyUid,
      userName,
      lat: optionalStringValue(data.lat),
      lng: optionalStringValue(data.lng),
      batteryLevel: optionalStringValue(data.batteryLevel),
      currentTripId: getOptionalString(data.currentTripId) ?? '',
    },
    android: {
      priority: 'HIGH',
      notification: {
        channel_id: sosEmergencyChannelId,
        sound: 'default',
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
    },
  };
}

function getFirebaseConfig(env: Env): FirebaseConfig {
  return {
    projectId: env.FIREBASE_PROJECT_ID?.trim() ?? '',
    clientEmail: env.FIREBASE_CLIENT_EMAIL?.trim() ?? '',
    privateKey: env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n').trim() ?? '',
  };
}

function assertFirebaseConfig(firebaseConfig: FirebaseConfig): void {
  if (
    firebaseConfig.projectId.length === 0 ||
    firebaseConfig.clientEmail.length === 0 ||
    firebaseConfig.privateKey.length === 0
  ) {
    throw new Error('Firebase configuration is incomplete');
  }
}

async function getAccessToken(
  env: Env,
  scope = firebaseMessagingScope,
): Promise<string> {
  const jwt = await createJwt(env, scope);
  const response = await fetch(googleOAuthTokenUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }).toString(),
  });

  const body = await readJsonOrText(response);
  if (!response.ok) {
    throw new Error(JSON.stringify(body));
  }

  if (!isRecord(body) || typeof body.access_token !== 'string') {
    throw new Error('OAuth response did not contain an access token');
  }

  return body.access_token;
}

async function createJwt(env: Env, scope: string): Promise<string> {
  const firebaseConfig = getFirebaseConfig(env);
  assertFirebaseConfig(firebaseConfig);
  const now = Math.floor(Date.now() / 1000);

  const header = {
    alg: 'RS256',
    typ: 'JWT',
  };

  const payload = {
    iss: firebaseConfig.clientEmail,
    scope,
    aud: googleOAuthTokenUrl,
    iat: now,
    exp: now + 3600,
  };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const unsignedJwt = `${encodedHeader}.${encodedPayload}`;
  const privateKey = await importPrivateKey(firebaseConfig.privateKey);
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(unsignedJwt),
  );

  return `${unsignedJwt}.${base64UrlEncode(signature)}`;
}

async function importPrivateKey(privateKeyPem: string): Promise<CryptoKey> {
  const pemContents = privateKeyPem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '');
  const binaryDer = base64ToArrayBuffer(pemContents);

  return crypto.subtle.importKey(
    'pkcs8',
    binaryDer,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign'],
  );
}

function base64UrlEncode(input: string | ArrayBuffer | Uint8Array): string {
  const bytes =
    typeof input === 'string' ? new TextEncoder().encode(input) : input;
  const base64 = arrayBufferToBase64(bytes);

  return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function base64ToArrayBuffer(base64: string): ArrayBuffer {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);

  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }

  return bytes.buffer;
}

function arrayBufferToBase64(buffer: ArrayBuffer | Uint8Array): string {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  let binary = '';

  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary);
}

async function parseJsonBody<T>(
  request: Request,
): Promise<{ ok: true; value: T } | { ok: false }> {
  try {
    const value = await request.json();

    if (!isRecord(value)) {
      return { ok: false };
    }

    return { ok: true, value: value as T };
  } catch {
    return { ok: false };
  }
}

function validateSosBody(body: SosRequestBody): string | null {
  if (isBlankString(body.userId)) {
    return 'userId is required';
  }

  if (isBlankString(body.familyUid)) {
    return 'familyUid is required';
  }

  if (isBlankString(body.userName)) {
    return 'userName is required';
  }

  return null;
}

function getRequiredString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function isBlankString(value: unknown): boolean {
  return typeof value !== 'string' || value.trim().length === 0;
}

function getOptionalString(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function optionalStringValue(value: unknown): string {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return String(value);
  }

  if (typeof value === 'string') {
    return value;
  }

  return '';
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function readFirestoreStringField(
  document: unknown,
  fieldName: string,
): string | null {
  if (!isRecord(document) || !isRecord(document.fields)) {
    return null;
  }

  const field = document.fields[fieldName];
  if (!isRecord(field) || typeof field.stringValue !== 'string') {
    return null;
  }

  const value = field.stringValue.trim();
  return value.length > 0 ? value : null;
}

async function readJsonOrText(response: Response): Promise<unknown> {
  const text = await response.text();
  if (text.length === 0) {
    return {};
  }

  try {
    return JSON.parse(text) as unknown;
  } catch {
    return text;
  }
}

function toPublicError(error: unknown): unknown {
  if (error instanceof Error) {
    try {
      return JSON.parse(error.message) as unknown;
    } catch {
      return error.message;
    }
  }

  return 'Unknown error';
}

function jsonResponse(
  body: unknown,
  status = 200,
  extraHeaders: HeadersInit = {},
): Response {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      ...corsHeaders,
      ...extraHeaders,
    },
  });
}
