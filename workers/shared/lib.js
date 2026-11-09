
/**
 * Shared Module Core Utility Library for KijaniKiosk Capstone Workers
 */

// 1. Structured JSON Logger
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

// 2. Order ID Verification regex matching ^[A-Za-z0-9][A-Za-z0-9-]{2,63}$
export function isValidOrderId(orderId) {
  if (!orderId || typeof orderId !== 'string') return false;
  const regex = /^[A-Za-z0-9][A-Za-z0-9-]{2,63}$/;
  return regex.test(orderId);
}

// 3. Async Web Crypto API SHA-256 Engine
export async function generateSha256(message) {
  const msgBuffer = new TextEncoder().encode(message);
  const hashBuffer = await crypto.subtle.digest('SHA-256', msgBuffer);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}

// 4. Constant-Time Authentication Check (Prevents timing attacks)
export function isAuthenticated(request, expectedKey) {
  if (!expectedKey) return false; // Fails closed if token variable is absent
  
  const providedKey = request.headers.get("x-api-key");
  if (!providedKey || providedKey.length !== expectedKey.length) return false;
  
  let result = 0;
  for (let i = 0; i < expectedKey.length; i++) {
    result |= providedKey.charCodeAt(i) ^ expectedKey.charCodeAt(i);
  }
  return result === 0;
}

// 5. Universal Queue Processing Batch Consumer Frame
export async function consume(batch, serviceName, handler) {
  const log = createLogger(serviceName);
  
  for (const message of batch.messages) {
    try {
      let body = message.body;
      
      // Handle string payloads passed via ingestion loops
      if (typeof body === 'string') {
        try { body = JSON.parse(body); } catch (_) {}
      }

      // Safe Check: Print unrecognised shape schemas to verify the unconfirmed R2 event layout
      if (!body || !body.object || !body.object.key) {
        log.error("event.unrecognised", null, "Unverified message payload or missing object key descriptor", { rawPayload: body });
        message.ack();
        continue;
      }

      const objectKey = body.object.key;
      
      // Invoke target specialized step logic
      const outcome = await handler(objectKey, body, message);
      
      if (outcome && outcome.action === "QUARANTINE") {
        log.error("receipt.rejected", outcome.orderId, "Permanent payload processing failure. Object quarantined.", { key: objectKey });
        message.ack(); // Permanently acknowledge to pull out from pipeline mechanics
      } else {
        message.ack(); // Happy Path confirmation
      }
      
    } catch (err) {
      log.error("message.transient_failure", null, err.message);
      // Fallback fallback loop logic targeting retry threshold limits
      if (message.attempts >= 3) {
        // Automatically dropped out to Cloudflare Queue native Dead Letter Queue bindings
        log.error("message.to_dlq", null, "Max retries exceeded. Message falling back to DLQ.");
      } else {
        message.retry();
      }
    }
  }
}
