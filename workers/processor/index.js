import { createLogger, generateSha256, consume } from '../shared/lib.js';

const log = createLogger("kk-processor");

export default {
  // Purely Asynchronous Queue Consumer (No HTTP Fetch Handler Surface)
  async queue(batch, env) {
    await consume(batch, "kk-processor", async (key, body, message) => {
      const orderId = body.orderId;
      
      // Receipt Enrichment Phase
      const processedAt = new Date().toISOString();
      const rawDataString = `${body.receiptId}-${orderId}-${body.amount}-${processedAt}`;
      const checksum = await generateSha256(rawDataString);

      const processedPayload = {
        ...body,
        processedAt,
        checksum,
        processorVersion: "1.0.0"
      };

      // Write refined payload upstream to the processed state R2 bucket
      const targetFilename = `processed-${body.receiptId}.json`;
      await env.PROCESSED_BUCKET.put(targetFilename, JSON.stringify(processedPayload));
      
      log.info("receipt.processed", orderId, { key: targetFilename });

      // Forward transaction message downstream to the notification producer queue
      await env.NOTIFY_QUEUE.send(processedPayload);
      return { action: "PROCEED", orderId };
    });
  }
};
