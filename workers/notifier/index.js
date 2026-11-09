import { createLogger, consume } from '../shared/lib.js';

const log = createLogger("kk-notifier");

export default {
  // Pure Asynchronous Queue Consumer Layout
  async queue(batch, env) {
    await consume(batch, "kk-notifier", async (key, body, message) => {
      const orderId = body.orderId;
      const channel = env.NOTIFICATION_CHANNEL || "log";
      const deliveredAt = new Date().toISOString();

      // Track distribution milestone
      log.info("notification.dispatched", orderId, { channel });

      const deliveryPayload = {
        ...body,
        deliveredAt,
        notificationChannel: channel
      };

      const targetFilename = `delivered-${body.receiptId}.json`;

      // Write transaction record to target R2 storage bucket with custom headers attached
      await env.DELIVERED_BUCKET.put(targetFilename, JSON.stringify(deliveryPayload), {
        customMetadata: {
          orderId: orderId,
          amount: String(body.amount),
          currency: body.currency,
          deliveredAt: deliveredAt
        }
      });

      log.info("receipt.delivered", orderId, { key: targetFilename });

      // Append transaction message payload frame downstream onto your analytics queue
      await env.DELIVERED_QUEUE.send(deliveryPayload);
      return { action: "PROCEED", orderId };
    });
  }
};
