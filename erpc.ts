import { createConfig } from "@erpc-cloud/config";

export default createConfig({
  // Logging verbosity: debug, info, warn, error, trace
  logLevel: "info",

  // Define one or more projects; here we use "main"
  projects: [
    {
      id: "main",
      upstreams: [
        {
          // Use Alchemy for any supported chain via environment variable
          endpoint: `alchemy://${process.env.ALCHEMY_API_KEY}`,
          // Optional: customize JSON-RPC options
          jsonRpc: {
            // e.g., send specific headers if needed:
            // headers: { Authorization: `Bearer ${process.env.ALCHEMY_AUTH_TOKEN}` }
            supportsBatch: true,
            batchMaxSize: 10,
            batchMaxWait: "100ms"
          }
        }
      ]
    }
  ]
});
