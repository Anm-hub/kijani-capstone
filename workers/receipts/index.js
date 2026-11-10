import { createLogger, isValidOrderId, generateSha256, isAuthenticated, consume, readJson } from '../shared/lib.js';

const log = createLogger("kk-receipts");

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return new Response(JSON.stringify({ status: "UP", service: "kk-receipts" }), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }

    if (url.pathname === "/receipts" && request.method === "POST") {
      if (!isAuthenticated(request, env.API_KEY)) {
        return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
      }

      try {
        const body = await request.json();
        const orderId = body.orderId;
        const amount = parseFloat(body.amount);

        if (!isValidOrderId(orderId) || isNaN(amount) || amount <= 0) {
          return new Response(JSON.stringify({ error: "Invalid layout rules or parameters" }), { status: 400 });
        }

        const targetFilename = `receipt-${orderId}.json`;
        const payloadData = {
          orderId,
          amount,
          currency: body.currency || env.DEFAULT_CURRENCY || "KES",
          submittedAt: new Date().toISOString()
        };

        await env.RECEIPTS_BUCKET.put(targetFilename, JSON.stringify(payloadData));
        log.info("receipt.ingested", orderId, { key: targetFilename });

        return new Response(JSON.stringify({ status: "Accepted", orderId }), {
          status: 202,
          headers: { "Content-Type": "application/json" }
        });
      } catch (err) {
        return new Response(JSON.stringify({ error: "Invalid JSON structure matrix" }), { status: 400 });
      }
    }
    return new Response(JSON.stringify({ error: "Not Found" }), { status: 404 });
  },

  async queue(batch, env) {
    await consume(batch, "kk-receipts", async (key, body) => {
      // Pull actual payload straight from R2 storage bucket
      const receipt = await readJson(env.RECEIPTS_BUCKET, key);
      
      const currency = receipt.currency || env.DEFAULT_CURRENCY || "KES";
      if (!receipt.amount || receipt.amount <= 0 || !["KES", "USD"].includes(currency)) {
        await env.PROCESSED_BUCKET.put(`quarantine-${key}`, JSON.stringify({ ...receipt, rejectionReason: "Invalid currency or values" }));
        return { action: "QUARANTINE", orderId: receipt.orderId };
      }

      const hash = await generateSha256(receipt.orderId);
      const receiptId = `RCP-${hash.substring(0, 12)}`;

      const processedData = {
        receiptId,
        orderId: receipt.orderId,
        amount: receipt.amount,
        currency: currency,
        issuedAt: new Date().toISOString()
      };

      const outKey = `processed-${receipt.orderId}.json`;
      await env.PROCESSED_BUCKET.put(outKey, JSON.stringify(processedData));
      log.info("receipt.generated", receipt.orderId, { key: outKey });
      
      return { action: "PROCEED", orderId: receipt.orderId };
    });
  }
};

