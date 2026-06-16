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
  sosId?: unknown;
};

type TestFcmRequestBody = {
  token?: unknown;
  title?: unknown;
  body?: unknown;
  userId?: unknown;
  familyUid?: unknown;
  lat?: unknown;
  lng?: unknown;
  batteryLevel?: unknown;
  currentTripId?: unknown;
  sosId?: unknown;
};

type FirebaseIdTokenPayload = {
  aud?: unknown;
  iss?: unknown;
  exp?: unknown;
  iat?: unknown;
  sub?: unknown;
  user_id?: unknown;
};

const firebaseMessagingScope =
  'https://www.googleapis.com/auth/firebase.messaging';
const firebaseMessagingAndDatastoreScope =
  'https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/datastore';
const googleOAuthTokenUrl = 'https://oauth2.googleapis.com/token';
const firebaseSecureTokenCertsUrl =
  'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';

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

  const bearerToken = getBearerToken(request);
  if (bearerToken.status === 'missing') {
    return jsonResponse(
      {
        success: false,
        message: 'Missing authorization token',
      },
      401,
    );
  }

  if (bearerToken.status === 'invalid') {
    return jsonResponse(
      {
        success: false,
        message: 'Invalid authorization header',
      },
      401,
    );
  }
  const idToken = (bearerToken as { status: 'ok'; token: string }).token;

  console.log('[send-sos] token received');

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

  let decodedToken: FirebaseIdTokenPayload;
  try {
    decodedToken = await verifyFirebaseIdToken(idToken, env);
    console.log('[send-sos] token verified');
  } catch {
    return jsonResponse(
      {
        success: false,
        message: 'Invalid authorization token',
      },
      401,
    );
  }

  try {
    const authUid = getAuthUid(decodedToken);
    const requestUserId = getRequiredString(body.value.userId);
    if (authUid !== requestUserId) {
      return jsonResponse(
        {
          success: false,
          message: 'User ID does not match authenticated user',
        },
        403,
      );
    }
    console.log('[send-sos] uid matched');

    const accessToken = await getAccessToken(
      env,
      firebaseMessagingAndDatastoreScope,
    );
    const userIsValid = await isTunaNetraUser(env, authUid, accessToken);
    if (!userIsValid) {
      return jsonResponse(
        {
          success: false,
          message: 'Authenticated user is not a tunanetra user',
        },
        403,
      );
    }

    const familyUid = getRequiredString(body.value.familyUid);
    const relationshipIsValid = await isFamilyPairedWithUser(
      env,
      familyUid,
      authUid,
      accessToken,
    );
    if (!relationshipIsValid) {
      return jsonResponse(
        {
          success: false,
          message: 'Family user is not paired with this user',
        },
        403,
      );
    }
    console.log('[send-sos] relationship verified');

    const result = await sendSosNotification(env, body.value, accessToken);

    if (result.tokenCount === 0) {
      return jsonResponse(
        {
          success: false,
          message: 'No FCM tokens found for this family user',
        },
        404,
      );
    }

    if (result.sentCount === 0) {
      console.log(`[send-sos] All ${result.tokenCount} token(s) stale/rejected, no message delivered`);
      return jsonResponse(
        {
          success: false,
          message: 'All FCM tokens were stale or rejected by FCM',
          sentCount: result.sentCount,
          failedCount: result.failedCount,
        },
        500,
      );
    }

    console.log('[send-sos] SOS sent');
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
  // Development-only endpoint for manually testing FCM delivery.
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
        data: {
          type: 'sos',
          title,
          body: notificationBody,
          userId,
          familyUid: getOptionalString(body.familyUid) ?? '',
          lat,
          lng,
          batteryLevel: optionalStringValue(body.batteryLevel),
          currentTripId: getOptionalString(body.currentTripId) ?? '',
          sosId: getOptionalString(body.sosId) ?? '',
        },
        android: {
          priority: 'HIGH',
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
  accessToken?: string,
): Promise<{ tokenCount: number; sentCount: number; failedCount: number }> {
  const familyUid = getRequiredString(data.familyUid);
  const authAccessToken =
    accessToken ??
    (await getAccessToken(env, firebaseMessagingAndDatastoreScope));
  const tokens = await getFamilyFcmTokens(env, familyUid, authAccessToken);

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
    tokens.map(async ({ token, documentName }) => {
      const result = await sendFcmToToken(
        env,
        authAccessToken,
        token,
        createSosFcmPayload(data),
      );
      if (result.ok) {
        sentCount += 1;
      } else {
        failedCount += 1;
        if (result.stale) {
          console.log(`[send-sos] Deleting stale FCM token: ${documentName}`);
          await deleteStaleToken(env, documentName, authAccessToken);
        }
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
): Promise<{ token: string; documentName: string }[]> {
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

  const seen = new Set<string>();
  const tokens: { token: string; documentName: string }[] = [];
  for (const document of body.documents) {
    const fcmToken = readFirestoreStringField(document, 'token');
    const documentName =
      isRecord(document) && typeof document.name === 'string'
        ? document.name
        : '';
    if (fcmToken !== null && !seen.has(fcmToken) && documentName.length > 0) {
      seen.add(fcmToken);
      tokens.push({ token: fcmToken, documentName });
    }
  }

  return tokens;
}

async function sendFcmToToken(
  env: Env,
  accessToken: string,
  token: string,
  payload: Record<string, unknown>,
): Promise<{ ok: true } | { ok: false; stale: boolean }> {
  const firebaseConfig = getFirebaseConfig(env);
  assertFirebaseConfig(firebaseConfig);

  const url =
    `https://fcm.googleapis.com/v1/projects/` +
    `${encodeURIComponent(firebaseConfig.projectId)}/messages:send`;

  try {
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
      return { ok: false, stale: isStaleTokenError(body) };
    }

    return { ok: true };
  } catch {
    return { ok: false, stale: false };
  }
}

function isStaleTokenError(body: unknown): boolean {
  if (!isRecord(body)) return false;
  const error = body.error;
  if (!isRecord(error)) return false;
  const status = error.status;
  return status === 'UNREGISTERED' || status === 'INVALID_ARGUMENT';
}

async function deleteStaleToken(
  env: Env,
  documentName: string,
  accessToken: string,
): Promise<void> {
  try {
    const response = await fetch(
      `https://firestore.googleapis.com/v1/${documentName}`,
      {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${accessToken}` },
      },
    );
    if (!response.ok && response.status !== 404) {
      console.warn(
        `[send-sos] Failed to delete stale FCM token (status=${response.status})`,
      );
    }
  } catch (e) {
    console.warn(`[send-sos] deleteStaleToken error: ${e}`);
  }
}

function createSosFcmPayload(data: SosRequestBody): Record<string, unknown> {
  const userId = getRequiredString(data.userId);
  const familyUid = getRequiredString(data.familyUid);
  const userName = getRequiredString(data.userName);
  const title = '\u{1F6A8} SOS Darurat';
  const body = `${userName} membutuhkan bantuan segera`;

  return {
    data: {
      type: 'sos',
      title,
      body,
      userId,
      familyUid,
      userName,
      lat: optionalStringValue(data.lat),
      lng: optionalStringValue(data.lng),
      batteryLevel: optionalStringValue(data.batteryLevel),
      currentTripId: getOptionalString(data.currentTripId) ?? '',
      sosId: getOptionalString(data.sosId) ?? '',
    },
    android: {
      priority: 'HIGH',
      // notification field diperlukan agar Android menampilkan notifikasi
      // secara native saat app di background/terminated, tanpa bergantung
      // pada Flutter background handler yang bisa diblokir battery optimizer.
      notification: {
        title,
        body,
        channel_id: 'sos_emergency_channel_v3',
        sound: 'sos_alert',
        notification_priority: 'PRIORITY_MAX',
        default_vibrate_timings: false,
        vibrate_timings_millis: ['0', '1000', '500', '1000', '500', '1500'],
        visibility: 'PUBLIC',
      },
    },
    webpush: {
      headers: {
        Urgency: 'high',
      },
      notification: {
        title,
        body,
        icon: '/icons/Icon-192.png',
        badge: '/icons/Icon-192.png',
        requireInteraction: true,
        tag: `sos-${getOptionalString(data.sosId) ?? userId}`,
      },
      fcmOptions: {
        link: '/#/family/home',
      },
    },
  };
}

function getBearerToken(
  request: Request,
): { status: 'ok'; token: string } | { status: 'missing' | 'invalid' } {
  const authorization = request.headers.get('Authorization');
  if (authorization === null || authorization.trim().length === 0) {
    return { status: 'missing' };
  }

  const match = authorization.trim().match(/^Bearer\s+(.+)$/i);
  if (match === null || match[1].trim().length === 0) {
    return { status: 'invalid' };
  }

  return { status: 'ok', token: match[1].trim() };
}

async function verifyFirebaseIdToken(
  idToken: string,
  env: Env,
): Promise<FirebaseIdTokenPayload> {
  const jwtParts = idToken.split('.');
  if (jwtParts.length !== 3) {
    throw new Error('Invalid Firebase ID token');
  }

  const header = decodeJwtPart(jwtParts[0]);
  const payload = decodeJwtPart(jwtParts[1]) as FirebaseIdTokenPayload;
  if (!isRecord(header) || header.alg !== 'RS256') {
    throw new Error('Invalid Firebase ID token algorithm');
  }

  const kid = typeof header.kid === 'string' ? header.kid : '';
  if (kid.length === 0) {
    throw new Error('Firebase ID token kid is missing');
  }

  validateFirebaseClaims(payload, env);

  const certResponse = await fetch(firebaseSecureTokenCertsUrl);
  const certs = await readJsonOrText(certResponse);
  if (!certResponse.ok || !isRecord(certs)) {
    throw new Error('Unable to fetch Firebase public certificates');
  }

  const certificate = certs[kid];
  if (typeof certificate !== 'string' || certificate.trim().length === 0) {
    throw new Error('Firebase public certificate not found');
  }

  const publicKey = await importX509Certificate(certificate);
  const signatureIsValid = await verifyJwtSignature(idToken, publicKey);
  if (!signatureIsValid) {
    throw new Error('Firebase ID token signature is invalid');
  }

  return payload;
}

function decodeJwtPart(part: string): Record<string, unknown> {
  const json = new TextDecoder().decode(base64UrlToUint8Array(part));
  const decoded = JSON.parse(json) as unknown;
  if (!isRecord(decoded)) {
    throw new Error('Invalid JWT payload');
  }

  return decoded;
}

async function importX509Certificate(certificatePem: string): Promise<CryptoKey> {
  const pemContents = certificatePem
    .replace('-----BEGIN CERTIFICATE-----', '')
    .replace('-----END CERTIFICATE-----', '')
    .replace(/\s/g, '');
  const certificateDer = base64ToArrayBuffer(pemContents);
  const subjectPublicKeyInfo = extractSubjectPublicKeyInfo(certificateDer);

  return crypto.subtle.importKey(
    'spki',
    subjectPublicKeyInfo,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['verify'],
  );
}

async function verifyJwtSignature(
  idToken: string,
  publicKey: CryptoKey,
): Promise<boolean> {
  const jwtParts = idToken.split('.');
  if (jwtParts.length !== 3) {
    return false;
  }

  const signedContent = `${jwtParts[0]}.${jwtParts[1]}`;
  const signature = base64UrlToUint8Array(jwtParts[2]);

  return crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    publicKey,
    signature,
    new TextEncoder().encode(signedContent),
  );
}

function validateFirebaseClaims(
  payload: FirebaseIdTokenPayload,
  env: Env,
): void {
  const firebaseConfig = getFirebaseConfig(env);
  assertFirebaseConfig(firebaseConfig);

  const now = Math.floor(Date.now() / 1000);
  const issuer = `https://securetoken.google.com/${firebaseConfig.projectId}`;
  if (payload.aud !== firebaseConfig.projectId) {
    throw new Error('Firebase ID token audience is invalid');
  }

  if (payload.iss !== issuer) {
    throw new Error('Firebase ID token issuer is invalid');
  }

  if (typeof payload.exp !== 'number' || payload.exp <= now) {
    throw new Error('Firebase ID token is expired');
  }

  if (
    typeof payload.iat !== 'number' ||
    payload.iat > now + 300 ||
    payload.iat <= 0
  ) {
    throw new Error('Firebase ID token issued-at claim is invalid');
  }

  const authUid = getAuthUid(payload);
  if (authUid.length === 0) {
    throw new Error('Firebase ID token subject is missing');
  }
}

function getAuthUid(payload: FirebaseIdTokenPayload): string {
  const userId = typeof payload.user_id === 'string' ? payload.user_id : '';
  const subject = typeof payload.sub === 'string' ? payload.sub : '';
  return userId.trim() || subject.trim();
}

async function isTunaNetraUser(
  env: Env,
  userUid: string,
  accessToken: string,
): Promise<boolean> {
  const document = await getFirestoreDocument(
    env,
    `users/${userUid}`,
    accessToken,
  );
  const userType = readFirestoreStringField(document, 'userType');
  return userType === 'tunanetra' || userType === 'UserType.tunanetra';
}

async function isFamilyPairedWithUser(
  env: Env,
  familyUid: string,
  tunaNetraUid: string,
  accessToken: string,
): Promise<boolean> {
  const document = await getFirestoreDocument(
    env,
    `users/${familyUid}`,
    accessToken,
  );
  const userType = readFirestoreStringField(document, 'userType');
  const isFamilyUser =
    userType === 'family' || userType === 'UserType.family';
  if (!isFamilyUser) {
    return false;
  }

  const pairedUserUid = readFirestoreStringField(document, 'pairedUserUid');
  if (pairedUserUid === tunaNetraUid) {
    return true;
  }

  const pairedUserUids = readFirestoreStringArrayField(
    document,
    'pairedUserUids',
  );
  if (pairedUserUids.includes(tunaNetraUid)) {
    return true;
  }

  const tunaNetraDocument = await getFirestoreDocument(
    env,
    `users/${tunaNetraUid}`,
    accessToken,
  );
  const connectedFamilyUids = readConnectedFamilyUids(tunaNetraDocument);
  if (connectedFamilyUids.includes(familyUid)) {
    return true;
  }

  const familyMemberDocument = await getFirestoreDocument(
    env,
    `users/${tunaNetraUid}/family_members/${familyUid}`,
    accessToken,
  );

  return familyMemberDocument !== null;
}

async function getFirestoreDocument(
  env: Env,
  documentPath: string,
  accessToken: string,
): Promise<unknown> {
  const firebaseConfig = getFirebaseConfig(env);
  assertFirebaseConfig(firebaseConfig);
  const path = documentPath
    .split('/')
    .map((segment) => encodeURIComponent(segment))
    .join('/');
  const url =
    `https://firestore.googleapis.com/v1/projects/` +
    `${encodeURIComponent(firebaseConfig.projectId)}` +
    `/databases/(default)/documents/${path}`;

  const response = await fetch(url, {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });

  if (response.status === 404) {
    return null;
  }

  const body = await readJsonOrText(response);
  if (!response.ok) {
    throw new Error(JSON.stringify(body));
  }

  return body;
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

function base64UrlToUint8Array(base64Url: string): Uint8Array {
  const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
  const padded = base64.padEnd(
    base64.length + ((4 - (base64.length % 4)) % 4),
    '=',
  );
  return new Uint8Array(base64ToArrayBuffer(padded));
}

function arrayBufferToBase64(buffer: ArrayBuffer | Uint8Array): string {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  let binary = '';

  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary);
}

type Asn1Element = {
  tag: number;
  start: number;
  valueStart: number;
  valueEnd: number;
  end: number;
};

function extractSubjectPublicKeyInfo(certificateDer: ArrayBuffer): ArrayBuffer {
  const bytes = new Uint8Array(certificateDer);
  const certificate = readAsn1Element(bytes, 0);
  if (certificate.tag !== 0x30) {
    throw new Error('Invalid X509 certificate');
  }

  const tbsCertificate = readAsn1Element(bytes, certificate.valueStart);
  if (tbsCertificate.tag !== 0x30) {
    throw new Error('Invalid X509 certificate body');
  }

  let offset = tbsCertificate.valueStart;
  const maybeVersion = readAsn1Element(bytes, offset);
  if (maybeVersion.tag === 0xa0) {
    offset = maybeVersion.end;
  }

  // serialNumber, signature, issuer, validity, subject
  for (let i = 0; i < 5; i += 1) {
    offset = readAsn1Element(bytes, offset).end;
  }

  const subjectPublicKeyInfo = readAsn1Element(bytes, offset);
  if (subjectPublicKeyInfo.tag !== 0x30) {
    throw new Error('X509 certificate public key is missing');
  }

  return bytes
    .slice(subjectPublicKeyInfo.start, subjectPublicKeyInfo.end)
    .buffer;
}

function readAsn1Element(bytes: Uint8Array, offset: number): Asn1Element {
  if (offset >= bytes.length) {
    throw new Error('Invalid ASN.1 offset');
  }

  const start = offset;
  const tag = bytes[offset];
  offset += 1;
  const firstLengthByte = bytes[offset];
  offset += 1;

  let length = firstLengthByte;
  if ((firstLengthByte & 0x80) !== 0) {
    const lengthBytes = firstLengthByte & 0x7f;
    if (lengthBytes === 0 || lengthBytes > 4) {
      throw new Error('Invalid ASN.1 length');
    }

    length = 0;
    for (let i = 0; i < lengthBytes; i += 1) {
      length = (length << 8) | bytes[offset];
      offset += 1;
    }
  }

  const valueStart = offset;
  const valueEnd = valueStart + length;
  if (valueEnd > bytes.length) {
    throw new Error('Invalid ASN.1 element length');
  }

  return {
    tag,
    start,
    valueStart,
    valueEnd,
    end: valueEnd,
  };
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

function readFirestoreStringArrayField(
  document: unknown,
  fieldName: string,
): string[] {
  if (!isRecord(document) || !isRecord(document.fields)) {
    return [];
  }

  const field = document.fields[fieldName];
  if (!isRecord(field) || !isRecord(field.arrayValue)) {
    return [];
  }

  const values = field.arrayValue.values;
  if (!Array.isArray(values)) {
    return [];
  }

  return values
    .map((value) =>
      isRecord(value) && typeof value.stringValue === 'string'
        ? value.stringValue.trim()
        : '',
    )
    .filter((value) => value.length > 0);
}

function readConnectedFamilyUids(document: unknown): string[] {
  if (!isRecord(document) || !isRecord(document.fields)) {
    return [];
  }

  const field = document.fields.connectedFamilies;
  if (!isRecord(field) || !isRecord(field.arrayValue)) {
    return [];
  }

  const values = field.arrayValue.values;
  if (!Array.isArray(values)) {
    return [];
  }

  return values
    .map((value) => {
      if (!isRecord(value) || !isRecord(value.mapValue)) {
        return '';
      }

      const fields = value.mapValue.fields;
      if (!isRecord(fields)) {
        return '';
      }

      const uid = fields.uid;
      return isRecord(uid) && typeof uid.stringValue === 'string'
        ? uid.stringValue.trim()
        : '';
    })
    .filter((value) => value.length > 0);
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
