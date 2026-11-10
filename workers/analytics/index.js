import { createLogger, consume, isAuthenticated } from '../shared/lib.js';

const log = createLogger("kk-analytics");

async function generateSummary(env) {
  let count = 0;
  const totals = {};
  let minDeliveredAt = null;
  let maxDeliveredAt = null;

  // Known limit: list() is single-page capped near 500 items
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

  return { count, totals, timeWindow: { start: minDeliveredAt, end: maxDeliveredAt } };
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return new Response(JSON.stringify({ status: "UP", service: "kk-analytics" }), { status: 200 });
    }

    if (!isAuthenticated(request, env.API_KEY)) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
    }

    if (url.pathname === "/summary" && request.method === "GET") {
      const summary = await generateSummary(env);
      return new Response(JSON.stringify(summary), { status: 200 });
    }

    if (url.pathname.startsWith("/delivered/") && request.method === "GET") {
      const orderId = url.pathname.split("/")[2];
      try {
        const targetKey = `delivered-${orderId}.json`;
        const obj = await env.DELIVERED_BUCKET.get(targetKey);
        if (!obj) return new Response(JSON.stringify({ error: "Record not found" }), { status: 404 });
        return new Response(JSON.stringify(await obj.json()), { status: 200 });
      } catch (err) {
        return new Response(JSON.stringify({ error: err.message }), { status: 500 });
      }
    }

    return new Response(JSON.stringify({ error: "Not Found" }), { status: 404 });
  },

  async queue(batch, env) {
    await consume(batch, "kk-analytics", async (key, body) => {
      const summary = await generateSummary(env);
      log.info("analytics.summary", null, {
        metricsCount: summary.count,
        currencyAggregates: summary.totals
      });
      return { action: "PROCEED", orderId: null };
    });
  }
};

