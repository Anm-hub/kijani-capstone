import { createLogger, isValidOrderId, generateSha256, isAuthenticated, consume } from '../shared/lib.js';

const log = createLogger("kk-receipts");

export default {
  // Public-facing API Ingestion Engine
  async fetch(request, env) {
    const url = new URL(request.url);

    // Open Endpoint Check
    if (url.pathname === "/health") {
      return new Response(JSON.stringify({ status: "UP", service: "kk-receipts" }), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }

    // Secure Route Traffic Handshake
    if (url.pathname === "/receipts" && request.method === "POST") {
      if (!isAuthenticated(request, env.API_KEY)) {
        return new Response(JSON.stringify({ error: "Unauthorized" }), {
          status: 401,
          headers: { "Content-Type": "application/json" }
        });
      }

      try {
        const body = await request.json();
        const orderId = body.orderId;

        // Semantic Boundary Validation
        if (!isValidOrderId(orderId)) {
          log.error("receipt.rejected", null, "Invalid orderId formatting structure presented");
          return new Response(JSON.stringify({ error: "Invalid orderId layout structure" }), { status: 400 });
        }

        // Deterministic Idempotence Pattern: Hash generation
        const hash = await generateSha256(orderId);
        const receiptId = `RCP-${hash.substring(0, 12)}`;
        const targetFilename = `receipt-${receiptId}.json`;

        // Pass direct serialization parameters to the active Ingestion Storage Bucket
        const payloadData = {
          receiptId,
          orderId,
          amount: parseFloat(body.amount),
          currency: body.currency || env.DEFAULT_CURRENCY || "KES",
          timestamp: new Date().toISOString()
        };

        await env.RECEIPTS_BUCKET.put(targetFilename, JSON.stringify(payloadData));
        log.info("receipt.ingested", orderId, { receiptId, key: targetFilename });

        return new Response(JSON.stringify({ status: "Accepted", receiptId }), {
          status: 202,
          headers: { "Content-Type": "application/json" }
        });
      } catch (err) {
        log.error("receipt.failed", null, err.message);
        return new Response(JSON.stringify({ error: "Malformed payload entity data matrix" }), { status: 400 });
      }
    }

    return new Response(JSON.stringify({ error: "Not Found" }), { status: 404 });
  },

  // Internal Asynchronous Event Engine
  async queue(batch, env) {
    await consume(batch, "kk-receipts", async (key, body, message) => {
      // Basic business check parameters inside queue context
      if (!body.amount || body.amount <= 0 || !["KES", "USD"].includes(body.currency)) {
        // Quarantine Step: Write invalid data to the processing environment bucket prefix
        const badReceiptKey = `quarantine-${key}`;
        await env.PROCESSED_BUCKET.put(badReceiptKey, JSON.stringify({ ...body, rejectionReason: "Invalid amount or currency bounds" }));
        return { action: "QUARANTINE", orderId: body.orderId };
      }

      // Happy Path: Send message down via the next queue producer pipeline line
      await env.PROCESSED_QUEUE.send(body);
      return { action: "PROCEED", orderId: body.orderId };
    });
  }
};
