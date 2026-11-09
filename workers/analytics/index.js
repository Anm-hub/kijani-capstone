import { createLogger, consume, isAuthenticated } from '../shared/lib.js';

const log = createLogger("kk-analytics");

// Helper function to build metrics by parsing the bucket's custom metadata
async function generateSummary(env) {
  let count = 0;
  const totals = {};
  let minDeliveredAt = null;
  let maxDeliveredAt = null;

  // Scan objects from the delivered storage segment directly through metadata
  const listResult = await env.DELIVERED_BUCKET.list({ include: ['customMetadata'] });
  
  for (const obj of listResult.objects) {
    count++;
    const meta = obj.customMetadata || {};
    const amount = parseFloat(meta.amount || 0);
    const currency = meta.currency || "KES";

    if (amount > 0) {
      totals[currency] = (totals[currency] || 0) + amount;
    }

    if (meta.deliveredAt) {
      const ts = meta.deliveredAt;
      if (!minDeliveredAt || ts < minDeliveredAt) minDeliveredAt = ts;
      if (!maxDeliveredAt || ts > maxDeliveredAt) maxDeliveredAt = ts;
    }
  }

  return {
    count,
    totals,
    timeWindow: {
      start: minDeliveredAt,
      end: maxDeliveredAt
    }
  };
}

export default {
  // Public HTTP Management Interface Surface
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return new Response(JSON.stringify({ status: "UP", service: "kk-analytics" }), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }

    // Authenticated Metrics Inspection Access Point
    if (!isAuthenticated(request, env.API_KEY)) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" }
      });
    }

    if (url.pathname === "/summary" && request.method === "GET") {
      try {
        const summary = await generateSummary(env);
        return new Response(JSON.stringify(summary), {
          status: 200,
          headers: { "Content-Type": "application/json" }
        });
      } catch (err) {
        return new Response(JSON.stringify({ error: err.message }), { status: 500 });
      }
    }

    if (url.pathname.startsWith("/delivered/") && request.method === "GET") {
      const receiptId = url.pathname.split("/")[2];
      try {
        const targetKey = `delivered-${receiptId}.json`;
        const obj = await env.DELIVERED_BUCKET.get(targetKey);
        
        if (!obj) {
          return new Response(JSON.stringify({ error: "Record not found" }), { status: 404 });
        }

        const data = await obj.json();
        return new Response(JSON.stringify(data), {
          status: 200,
          headers: { "Content-Type": "application/json" }
        });
      } catch (err) {
        return new Response(JSON.stringify({ error: err.message }), { status: 500 });
      }
    }

    return new Response(JSON.stringify({ error: "Not Found" }), { status: 404 });
  },

  // Asynchronous Decoupled Event Batch Target
  async queue(batch, env) {
    await consume(batch, "kk-analytics", async (key, body, message) => {
      // Re-evaluate current aggregation state metrics
      const summary = await generateSummary(env);
      
      // Output required structured telemetry frame
      log.info("analytics.summary", null, {
        metricsCount: summary.count,
        currencyAggregates: summary.totals,
        window: summary.timeWindow
      });

      return { action: "PROCEED", orderId: body.orderId };
    });
  }
};
