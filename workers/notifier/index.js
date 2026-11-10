import { createLogger, consume, readJson } from '../shared/lib.js';

const log = createLogger("kk-notifier");

export default {
  async queue(batch, env) {
    await consume(batch, "kk-notifier", async (key) => {
      const payload = await readJson(env.NOTIFY_BUCKET, key);
      const channel = env.NOTIFICATION_CHANNEL || "log";
      const deliveredAt = new Date().toISOString();

      log.info("notification.dispatched", payload.orderId, { channel });

      const deliveryPayload = {
        ...payload,
        deliveredAt,
        notificationChannel: channel
      };

      const outKey = `delivered-${payload.orderId}.json`;
      await env.DELIVERED_BUCKET.put(outKey, JSON.stringify(deliveryPayload), {
        customMetadata: {
          orderId: payload.orderId,
          amount: String(payload.amount),
          currency: payload.currency,
          deliveredAt: deliveredAt
        }
      });

      log.info("receipt.delivered", payload.orderId, { key: outKey });
      return { action: "PROCEED", orderId: payload.orderId };
    });
  }
};

