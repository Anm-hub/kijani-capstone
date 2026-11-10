/**
 * Shared Module Core Utility Library for KijaniKiosk Capstone Workers
 */

export function createLogger(serviceName) {
  return {
    info: (eventName, orderId, extra = {}) => {
      console.log(JSON.stringify({
        service: serviceName,
        event: eventName,
        orderId: orderId || null,
        ts: new Date().toISOString(),
        level: "INFO",
        ...extra
      }));
    },
    error: (eventName, orderId, errorMsg, extra = {}) => {
      console.error(JSON.stringify({
        service: serviceName,
        event: eventName,
        orderId: orderId || null,
        ts: new Date().toISOString(),
        level: "ERROR",
        error: errorMsg,
        ...extra
      }));
    }
  };
}

export function isValidOrderId(orderId) {
  if (!orderId || typeof orderId !== 'string') return false;
  const regex = /^[A-Za-z0-9][A-Za-z0-9-]{2,63}$/;
  return regex.test(orderId);
}

export async function generateSha256(message) {
  const msgBuffer = new TextEncoder().encode(message);
  const hashBuffer = await crypto.subtle.digest('SHA-256', msgBuffer);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}

export function isAuthenticated(request, expectedKey) {
  if (!expectedKey) return false;
  const providedKey = request.headers.get("x-api-key");
  if (!providedKey || providedKey.length !== expectedKey.length) return false;
  
  let result = 0;
  for (let i = 0; i < expectedKey.length; i++) {
    result |= providedKey.charCodeAt(i) ^ expectedKey.charCodeAt(i);
  }
  return result === 0;
}

// Fetches an object from an R2 bucket and safely returns parsed JSON
export async function readJson(bucket, key) {
  const obj = await bucket.get(key);
  if (!obj) {
    throw new Error(`Target object key '${key}' not found in R2 storage bucket`);
  }
  return await obj.json();
}

export async function consume(batch, serviceName, handler) {
  const log = createLogger(serviceName);
  
  for (const message of batch.messages) {
    try {
      let body = message.body;
      if (typeof body === 'string') {
        try { body = JSON.parse(body); } catch (_) {}
      }

      // Safe Check: Fallback visibility for unconfirmed R2 event layout
      if (!body || !body.object || !body.object.key) {
        log.error("event.unrecognised", null, "Missing object key identifier", { rawPayload: body });
        message.ack();
        continue;
      }

      const objectKey = body.object.key;
      const outcome = await handler(objectKey, body, message);
      
      if (outcome && outcome.action === "QUARANTINE") {
        log.error("receipt.rejected", outcome.orderId, "Payload isolated.", { key: objectKey });
      }
      
      message.ack();
    } catch (err) {
      log.error("message.transient_failure", null, err.message);
      // Cloudflare native Queue handles DLQ routing after max_retries
      message.retry();
    }
  }
}

