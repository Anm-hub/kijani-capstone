import { createLogger, generateSha256, consume, readJson } from '../shared/lib.js';

const log = createLogger("kk-processor");

export default {
  async queue(batch, env) {
    await consume(batch, "kk-processor", async (key) => {
      const receipt = await readJson(env.PROCESSED_BUCKET, key);
      
      // Idempotent Checksum over predictable parameters without moving timestamps
      const rawDataString = `${receipt.receiptId}-${receipt.orderId}-${receipt.amount}-${receipt.currency}`;
      const checksum = await generateSha256(rawDataString);

      const enrichedPayload = {
        ...receipt,
        processedAt: new Date().toISOString(),
        checksum,
        processorVersion: "1.1.0"
      };

      const outKey = `notify-${receipt.orderId}.json`;
      await env.NOTIFY_BUCKET.put(outKey, JSON.stringify(enrichedPayload));
      log.info("receipt.processed", receipt.orderId, { key: outKey });

      return { action: "PROCEED", orderId: receipt.orderId };
    });
  }
};

